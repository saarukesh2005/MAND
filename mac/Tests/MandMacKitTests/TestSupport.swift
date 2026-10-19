import Foundation
import MandCore
@testable import MandMacKit
import Network
import Security

/// A throwaway keychain file so tests never touch the user's login keychain.
final class TemporaryKeychain {
    let keychain: SecKeychain
    let path: String

    init() throws {
        path = NSTemporaryDirectory() + "mand-test-\(UUID().uuidString).keychain"
        let password = "test"
        var keychain: SecKeychain?
        let status = SecKeychainCreate(path, UInt32(password.utf8.count), password, false, nil, &keychain)
        guard status == errSecSuccess, let keychain else {
            throw DeviceIdentity.IdentityError.keychain(status, "creating a test keychain")
        }
        self.keychain = keychain
    }

    func identity(_ name: String) throws -> DeviceIdentity {
        try DeviceIdentity.loadOrCreate(label: "M’AND Test \(name)", keychain: keychain, commonName: name)
    }

    deinit {
        SecKeychainDelete(keychain)
    }
}

/// Thread-safe log of things that happened, with an async wait helper.
final class Recorder<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [T] = []

    func append(_ item: T) { lock.withLock { items.append(item) } }
    var all: [T] { lock.withLock { items } }

    /// Polls until `predicate` finds a match or the timeout passes.
    func wait<R>(timeout: TimeInterval = 10, _ predicate: (T) -> R?) async -> R? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let match = all.lazy.compactMap(predicate).first { return match }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return nil
    }
}

/// Simulates the Android app well enough to exercise the real TLS server.
final class SimulatedPhone: @unchecked Sendable {
    let identity: DeviceIdentity
    let received = Recorder<Message>()
    let closed = Recorder<String>()
    let readyPeer = Recorder<Fingerprint?>()
    private let queue = DispatchQueue(label: "test.phone")
    private var framed: FramedConnection?

    init(identity: DeviceIdentity) { self.identity = identity }

    /// Connects, pinning the Mac's certificate fingerprint.
    func connect(port: UInt16, pinning mac: Fingerprint, name: String = "Test Phone") {
        let parameters = TLS.parameters(identity: identity, requireClientCertificate: false, queue: queue) { $0 == mac }
        let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: parameters)
        let framed = FramedConnection(connection: connection, queue: queue)
        self.framed = framed
        framed.start { [weak self, weak framed] event in
            guard let self else { return }
            switch event {
            case .ready(let peer):
                self.readyPeer.append(peer)
                framed?.send(.hello(Hello(name: name, platform: .android, versions: 1...1, app: "test")))
            case .envelope(let envelope): self.received.append(envelope.message)
            case .protocolViolation: break
            case .closed(let reason): self.closed.append(reason)
            }
        }
    }

    func send(_ message: Message) { queue.async { self.framed?.send(message) } }
    func disconnect() { queue.async { self.framed?.close(reason: "test disconnect") } }
}
