import Foundation
import MandCore
@testable import MandMacKit
import Testing

/// Real TLS 1.3 connections on localhost between BridgeServer and a simulated phone.
@Suite("Bridge server (localhost TLS)", .serialized)
final class BridgeServerTests {
    let keychain: TemporaryKeychain
    let macIdentity: DeviceIdentity
    let phoneIdentity: DeviceIdentity
    let events = Recorder<BridgeServer.Event>()
    var store: PairedDeviceStore = InMemoryPairedDeviceStore()
    var approve = true
    var approvalDelay: TimeInterval = 0
    var server: BridgeServer!

    init() throws {
        keychain = try TemporaryKeychain()
        macIdentity = try keychain.identity("Mac")
        phoneIdentity = try keychain.identity("Phone")
    }

    deinit { server?.stop() }

    /// Starts the server and returns its port. Approval requests are answered with `approve`.
    func startServer() async throws -> UInt16 {
        let shouldApprove = approve
        let delay = approvalDelay
        let box = ServerBox()
        server = BridgeServer(identity: macIdentity, store: store, deviceName: "Test Mac", preferredPort: 0,
                              advertise: false, addresses: { ["127.0.0.1"] }) { [events] event in
            events.append(event)
            if case .approvalNeeded(let request) = event {
                DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                    box.server?.resolvePairing(id: request.id, approved: shouldApprove)
                }
            }
        }
        box.server = server
        server.start()
        let port = await events.wait { if case .listening(let port) = $0 { port } else { nil } }
        // The trusted list loads separately; tests start once it has (or once it has failed).
        _ = await events.wait { event -> Bool? in
            switch event {
            case .devicesChanged: true
            case .trustedListProblem(let problem) where problem != nil: true
            default: nil
            }
        }
        return try #require(port)
    }

    /// Opens a new pairing window and returns its (fresh) invitation, not an earlier one.
    func openWindow() async throws -> PairingInvitation {
        let previous = events.all.compactMap { if case .pairingWindowOpened(let i) = $0 { i } else { nil } }.count
        server.openPairingWindow()
        let invitation = await events.wait(timeout: 10) { _ -> PairingInvitation? in
            let opened = self.events.all.compactMap { if case .pairingWindowOpened(let i) = $0 { i } else { nil } }
            return opened.count > previous ? opened.last : nil
        }
        return try #require(invitation)
    }

    func proof(_ invitation: PairingInvitation, phone: DeviceIdentity? = nil) -> String {
        PairingProof.compute(secret: invitation.secret, phone: (phone ?? phoneIdentity).fingerprint,
                             mac: invitation.fingerprint).base64URLEncoded
    }

    /// Full pairing flow; returns the connected phone.
    func pairedPhone(port: UInt16, identity: DeviceIdentity? = nil, name: String = "Test Phone") async throws -> SimulatedPhone {
        let identity = identity ?? phoneIdentity
        let invitation = try await openWindow()
        let phone = SimulatedPhone(identity: identity)
        phone.connect(port: port, pinning: invitation.fingerprint, name: name)
        _ = await phone.received.wait { if case .hello = $0 { true } else { nil } }
        phone.send(.pairRequest(proof: proof(invitation, phone: identity)))
        let ready = await phone.received.wait { $0 == .sessionReady ? true : nil }
        try #require(ready == true)
        return phone
    }

    @Test("Pairing with approval, then text flows both ways")
    func pairAndChat() async throws {
        let port = try await startServer()
        let phone = try await pairedPhone(port: port)

        #expect(phone.received.all.contains(.pairResult(accepted: true, reason: nil)))
        #expect(try store.load().map(\.fingerprint) == [phoneIdentity.fingerprint])
        #expect(phone.readyPeer.all.first == macIdentity.fingerprint)

        phone.send(.text("hello mac"))
        let text = await events.wait { if case .textReceived(let t, _) = $0 { t } else { nil } }
        #expect(text == "hello mac")

        server.sendText("hello phone", to: phoneIdentity.fingerprint)
        #expect(await phone.received.wait { $0 == .text("hello phone") ? true : nil } == true)
    }

    @Test("Pairing still succeeds when the user takes a few seconds to click Allow")
    func slowApproval() async throws {
        approvalDelay = 3 // longer than the server's 1 s housekeeping tick
        let port = try await startServer()
        let phone = try await pairedPhone(port: port)
        #expect(phone.received.all.contains(.pairResult(accepted: true, reason: nil)))
        #expect(try store.load().map(\.fingerprint) == [phoneIdentity.fingerprint])
    }

    @Test("Before pairing, a frame over 4 KiB is rejected and the connection closed")
    func preReadyFrameLimit() async throws {
        let port = try await startServer()
        let invitation = try await openWindow()
        let phone = SimulatedPhone(identity: phoneIdentity)
        phone.connect(port: port, pinning: invitation.fingerprint)
        _ = await phone.received.wait { if case .hello = $0 { true } else { nil } }
        phone.send(.text(String(repeating: "x", count: 5_000)))
        let code = await phone.received.wait { if case .error(let c, _) = $0 { c } else { nil } }
        #expect(code == "too_large")
        #expect(await phone.closed.wait { $0 } != nil)
    }

    @Test("Half-open connections from one address are capped")
    func pendingConnectionCap() async throws {
        let port = try await startServer()
        _ = try await openWindow()
        let phones = (0..<(BridgeServer.maxPendingPerAddress + 2)).map { _ in SimulatedPhone(identity: phoneIdentity) }
        for phone in phones {
            phone.connect(port: port, pinning: macIdentity.fingerprint)
            try await Task.sleep(for: .milliseconds(150))
        }
        try await Task.sleep(for: .seconds(1))
        let accepted = phones.filter { phone in phone.received.all.contains { if case .hello = $0 { true } else { false } } }
        #expect(accepted.count == BridgeServer.maxPendingPerAddress)
    }

    @Test("Phone names are cleaned of control and direction-override characters")
    func nameSanitising() {
        #expect(BridgeServer.displaySafe("Pixel\u{202E}9\n") == "Pixel9")
        #expect(BridgeServer.displaySafe("\u{200B}\u{0007}") == "Android phone")
        #expect(BridgeServer.displaySafe("Saarukesh’s Pixel") == "Saarukesh’s Pixel")
    }

    @Test("Two phones stay connected together; messages reach only their target")
    func twoPhones() async throws {
        let port = try await startServer()
        let second = try keychain.identity("Phone 2")
        let phoneA = try await pairedPhone(port: port, name: "Phone A")
        let phoneB = try await pairedPhone(port: port, identity: second, name: "Phone B")
        #expect(try store.load().count == 2)

        server.sendText("only A", to: phoneIdentity.fingerprint)
        server.sendText("only B", to: second.fingerprint)
        #expect(await phoneA.received.wait { $0 == .text("only A") ? true : nil } == true)
        #expect(await phoneB.received.wait { $0 == .text("only B") ? true : nil } == true)
        #expect(!phoneA.received.all.contains(.text("only B")))
        #expect(!phoneB.received.all.contains(.text("only A")))
        #expect(phoneA.closed.all.isEmpty) // the second phone did not replace the first
    }

    @Test("Forgetting one phone leaves the other connected")
    func forgetOneOfTwo() async throws {
        let port = try await startServer()
        let second = try keychain.identity("Phone 2")
        let phoneA = try await pairedPhone(port: port, name: "Phone A")
        let phoneB = try await pairedPhone(port: port, identity: second, name: "Phone B")
        server.forget(phoneIdentity.fingerprint)
        #expect(await phoneA.closed.wait { $0 } != nil)
        server.sendText("still here", to: second.fingerprint)
        #expect(await phoneB.received.wait { $0 == .text("still here") ? true : nil } == true)
        #expect(phoneB.closed.all.isEmpty)
        #expect(try store.load().map(\.fingerprint) == [second.fingerprint])
    }

    @Test("An address that sends 3 wrong pairing proofs is refused for a while")
    func perAddressThrottle() async throws {
        let port = try await startServer()
        let invitation = try await openWindow()
        for _ in 0..<BridgeServer.maxFailedProofsPerAddress {
            let attacker = SimulatedPhone(identity: phoneIdentity)
            attacker.connect(port: port, pinning: invitation.fingerprint)
            _ = await attacker.received.wait { if case .hello = $0 { true } else { nil } }
            attacker.send(.pairRequest(proof: Data(repeating: 1, count: 32).base64URLEncoded))
            #expect(await attacker.closed.wait { $0 } != nil)
        }
        let next = SimulatedPhone(identity: phoneIdentity)
        next.connect(port: port, pinning: invitation.fingerprint)
        let reason = await next.received.wait { if case .pairResult(false, let r) = $0 { r } else { nil } }
        #expect(reason == "pairing_too_many_attempts")
    }

    @Test("An unpaired phone is refused when no pairing window is open")
    func unpairedRefused() async throws {
        let port = try await startServer()
        let phone = SimulatedPhone(identity: phoneIdentity)
        phone.connect(port: port, pinning: macIdentity.fingerprint)
        #expect(await phone.closed.wait { $0 } != nil)
        #expect(!phone.received.all.contains(.sessionReady))
        #expect(try store.load().isEmpty)
    }

    @Test("A wrong pairing proof is rejected and nothing is stored")
    func wrongProof() async throws {
        let port = try await startServer()
        let invitation = try await openWindow()
        let phone = SimulatedPhone(identity: phoneIdentity)
        phone.connect(port: port, pinning: invitation.fingerprint)
        _ = await phone.received.wait { if case .hello = $0 { true } else { nil } }
        phone.send(.pairRequest(proof: Data(repeating: 7, count: 32).base64URLEncoded))

        let result = await phone.received.wait { if case .pairResult(false, let r) = $0 { r } else { nil } }
        #expect(result == "pairing_invalid")
        #expect(await phone.closed.wait { $0 } != nil)
        #expect(try store.load().isEmpty)
    }

    @Test("A proof copied by a different device (man-in-the-middle) is rejected")
    func proofBoundToCertificate() async throws {
        let port = try await startServer()
        let invitation = try await openWindow()
        let attacker = SimulatedPhone(identity: try keychain.identity("Attacker"))
        attacker.connect(port: port, pinning: invitation.fingerprint)
        _ = await attacker.received.wait { if case .hello = $0 { true } else { nil } }
        attacker.send(.pairRequest(proof: proof(invitation, phone: phoneIdentity))) // proof made for the real phone

        let result = await attacker.received.wait { if case .pairResult(false, let r) = $0 { r } else { nil } }
        #expect(result == "pairing_invalid")
    }

    @Test("Declining on the Mac rejects the phone")
    func declined() async throws {
        approve = false
        let port = try await startServer()
        let invitation = try await openWindow()
        let phone = SimulatedPhone(identity: phoneIdentity)
        phone.connect(port: port, pinning: invitation.fingerprint)
        _ = await phone.received.wait { if case .hello = $0 { true } else { nil } }
        phone.send(.pairRequest(proof: proof(invitation)))

        let result = await phone.received.wait { if case .pairResult(false, let r) = $0 { r } else { nil } }
        #expect(result == "pairing_rejected")
        #expect(try store.load().isEmpty)
    }

    @Test("The phone refuses a Mac whose certificate doesn't match the QR code")
    func phonePinsMac() async throws {
        let port = try await startServer()
        _ = try await openWindow()
        let phone = SimulatedPhone(identity: phoneIdentity)
        let impostor = try keychain.identity("Impostor").fingerprint
        phone.connect(port: port, pinning: impostor)
        #expect(await phone.closed.wait { $0 } != nil)
        #expect(phone.readyPeer.all.isEmpty)
    }

    @Test("A paired phone reconnects without pairing again")
    func reconnect() async throws {
        let port = try await startServer()
        let first = try await pairedPhone(port: port)
        first.disconnect()
        let disconnected = await events.wait { if case .phoneDisconnected = $0 { true } else { nil } }
        #expect(disconnected == true)

        let second = SimulatedPhone(identity: phoneIdentity)
        second.connect(port: port, pinning: macIdentity.fingerprint)
        #expect(await second.received.wait { $0 == .sessionReady ? true : nil } == true)
        #expect(!second.received.all.contains { if case .pairResult = $0 { true } else { false } })
    }

    @Test("A forgotten phone is told, disconnected, and refused next time")
    func forget() async throws {
        let port = try await startServer()
        let phone = try await pairedPhone(port: port)
        server.forget(phoneIdentity.fingerprint)

        #expect(await phone.received.wait { $0 == .bye(reason: "unpaired") ? true : nil } == true)
        #expect(await phone.closed.wait { $0 } != nil)
        #expect(try store.load().isEmpty)

        let again = SimulatedPhone(identity: phoneIdentity)
        again.connect(port: port, pinning: macIdentity.fingerprint)
        #expect(await again.closed.wait { $0 } != nil)
        #expect(!again.received.all.contains(.sessionReady))
    }

    @Test("Messages before pairing finishes are refused")
    func noTextBeforePairing() async throws {
        let port = try await startServer()
        let invitation = try await openWindow()
        let phone = SimulatedPhone(identity: phoneIdentity)
        phone.connect(port: port, pinning: invitation.fingerprint)
        _ = await phone.received.wait { if case .hello = $0 { true } else { nil } }
        phone.send(.text("sneaky"))

        #expect(await phone.closed.wait { $0 } != nil)
        #expect(!events.all.contains { if case .textReceived = $0 { true } else { false } })
    }

    @Test("If the paired list can't be read, a known phone keeps its pairing and connects after Try Again")
    func unreadableTrustedList() async throws {
        let flaky = FlakyStore()
        store = flaky
        let port = try await startServer()
        let paired = try await pairedPhone(port: port)
        paired.disconnect()
        _ = await events.wait { if case .phoneDisconnected = $0 { true } else { nil } }

        // Restart with a Keychain that refuses to open (e.g. the prompt was declined).
        server.stop()
        let savesBefore = flaky.saved.count
        flaky.failLoads = true
        events.clear()
        let port2 = try await startServer()
        #expect(events.all.contains { if case .trustedListProblem(let p) = $0 { p != nil } else { false } })

        let phone = SimulatedPhone(identity: phoneIdentity)
        phone.connect(port: port2, pinning: macIdentity.fingerprint)
        #expect(await phone.closed.wait { $0 } != nil)
        // The phone must never be told it isn't paired (it would delete its pairing).
        #expect(!phone.received.all.contains { if case .error(let code, _) = $0 { code == ProtocolError.notPaired.rawValue } else { false } })
        #expect(flaky.saved.count == savesBefore) // the stored list was not overwritten

        flaky.failLoads = false
        server.reloadDevices()
        _ = await events.wait { if case .devicesChanged(let d) = $0, !d.isEmpty { true } else { nil } }
        let again = SimulatedPhone(identity: phoneIdentity)
        again.connect(port: port2, pinning: macIdentity.fingerprint)
        #expect(await again.received.wait { $0 == .sessionReady ? true : nil } == true)
    }
}

/// Lets the event callback reach the server created after it.
private final class ServerBox: @unchecked Sendable {
    weak var server: BridgeServer?

}

/// A store whose reads can be made to fail, like a Keychain item the user declined access to.
final class FlakyStore: PairedDeviceStore, @unchecked Sendable {
    private let lock = NSLock()
    private var devices: [PairedDevice] = []
    private var _failLoads = false
    private(set) var saved: [[PairedDevice]] = []
    var failLoads: Bool {
        get { lock.withLock { _failLoads } }
        set { lock.withLock { _failLoads = newValue } }
    }
    struct Denied: Error {}

    func load() throws -> [PairedDevice] {
        try lock.withLock {
            if _failLoads { throw Denied() }
            return devices
        }
    }

    func save(_ devices: [PairedDevice]) throws {
        lock.withLock {
            self.devices = devices
            saved.append(devices)
        }
    }
}
