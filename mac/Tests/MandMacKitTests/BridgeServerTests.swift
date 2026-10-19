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
    let store = InMemoryPairedDeviceStore()
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
        return try #require(port)
    }

    func openWindow() async throws -> PairingInvitation {
        server.openPairingWindow()
        let invitation = await events.wait { if case .pairingWindowOpened(let i) = $0 { i } else { nil } }
        return try #require(invitation)
    }

    func proof(_ invitation: PairingInvitation, phone: DeviceIdentity? = nil) -> String {
        PairingProof.compute(secret: invitation.secret, phone: (phone ?? phoneIdentity).fingerprint,
                             mac: invitation.fingerprint).base64URLEncoded
    }

    /// Full pairing flow; returns the connected phone.
    func pairedPhone(port: UInt16) async throws -> SimulatedPhone {
        let invitation = try await openWindow()
        let phone = SimulatedPhone(identity: phoneIdentity)
        phone.connect(port: port, pinning: invitation.fingerprint)
        _ = await phone.received.wait { if case .hello = $0 { true } else { nil } }
        phone.send(.pairRequest(proof: proof(invitation)))
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

        server.sendText("hello phone")
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
}

/// Lets the event callback reach the server created after it.
private final class ServerBox: @unchecked Sendable {
    weak var server: BridgeServer?
}
