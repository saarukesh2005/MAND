import CryptoKit
import Foundation
import MandCore
@testable import MandQuickShare
import Network
import Testing

/// Records receiver events and answers consent requests automatically.
final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [QuickShareEvent] = []
    var accept = true
    weak var receiver: QuickShareReceiver?

    func handle(_ event: QuickShareEvent) {
        lock.withLock { events.append(event) }
        if case .requestNeedsConsent(let request) = event {
            let accept = self.accept
            DispatchQueue.main.async { self.receiver?.respond(to: request.id, accept: accept) }
        }
    }

    var all: [QuickShareEvent] { lock.withLock { events } }

    func wait<R>(timeout: TimeInterval = 15, _ match: (QuickShareEvent) -> R?) async -> R? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let found = all.lazy.compactMap(match).first { return found }
            try? await Task.sleep(for: .milliseconds(30))
        }
        return nil
    }
}

final class SenderDelegate: OutboundNearbyConnectionDelegate, @unchecked Sendable {
    func outboundConnectionWasEstablished(connection: OutboundNearbyConnection) {}
    func outboundConnection(connection: OutboundNearbyConnection, transferProgress: Double) {}
    func outboundConnectionTransferAccepted(connection: OutboundNearbyConnection) {}
    var errors: [String] = []
    func outboundConnection(connection: OutboundNearbyConnection, failedWithError: Error) { errors.append("\(failedWithError)") }
    func outboundConnectionTransferFinished(connection: OutboundNearbyConnection) {}
}

/// End-to-end: NearDrop's sender (ported to CryptoKit) → M’AND's Quick Share receiver over real
/// localhost TCP: UKEY2 key exchange, AES/HMAC SecureMessage, consent, and file saving.
@Suite("Quick Share receiver", .serialized)
@MainActor
final class QuickShareTests {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("mand-qs-\(UUID().uuidString)")
    var inbox: URL { root.appendingPathComponent("inbox") }
    var partials: URL { root.appendingPathComponent("partials") }
    let log = EventLog()
    var receiver: QuickShareReceiver!
    let senderDelegate = SenderDelegate()
    var sender: OutboundNearbyConnection?

    init() throws {
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    func startReceiver() async throws -> UInt16 {
        let log = self.log
        receiver = QuickShareReceiver(deviceName: "Test Mac", destination: { [inbox] in inbox }, partialFolder: partials) {
            log.handle($0)
        }
        log.receiver = receiver
        receiver.start()
        // The listener port is only known once it's ready; read it from the advertised service.
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if let port = receiver.listeningPort { return port }
            try await Task.sleep(for: .milliseconds(30))
        }
        throw NearbyError.inputOutput
    }

    func send(_ urls: [URL], port: UInt16, rename: ((String) -> String)? = nil) {
        let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        let sender = OutboundNearbyConnection(connection: connection, id: UUID().uuidString, urlsToSend: urls)
        sender.nameOverride = rename
        sender.delegate = senderDelegate
        self.sender = sender
        sender.start()
    }

    func file(_ name: String, bytes: Int) throws -> URL {
        let folder = root.appendingPathComponent("outbox")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        try Data((0..<bytes).map { _ in UInt8.random(in: 0...255) }).write(to: url)
        return url
    }

    @Test("A file sent over Quick Share arrives intact after the user accepts, with a PIN shown")
    func receivesFile() async throws {
        let port = try await startReceiver()
        let source = try file("holiday photo.jpg", bytes: 3_000_000)
        send([source], port: port)
        let request = await log.wait { if case .requestNeedsConsent(let r) = $0 { r } else { nil } }
        #expect(senderDelegate.errors.isEmpty)
        #expect(request?.fileNames == ["holiday photo.jpg"])
        #expect(request?.pinCode?.count == 4)
        #expect(request?.senderName == "Test Phone")
        let saved = await log.wait { if case .finished(_, _, let files, _, _) = $0 { files } else { nil } }
        let target = inbox.appendingPathComponent("holiday photo.jpg")
        #expect(saved == [target])
        #expect(try Data(contentsOf: target) == Data(contentsOf: source))
        #expect(try FileManager.default.contentsOfDirectory(atPath: partials.path).isEmpty)
    }

    @Test("Declining saves nothing")
    func declined() async throws {
        log.accept = false
        let port = try await startReceiver()
        send([try file("secret.pdf", bytes: 10_000)], port: port)
        _ = await log.wait { if case .requestNeedsConsent(let r) = $0 { r } else { nil } }
        try await Task.sleep(for: .seconds(1))
        #expect(try FileManager.default.contentsOfDirectory(atPath: inbox.path).isEmpty)
    }

    @Test("A traversal name can't escape the download folder")
    func maliciousName() async throws {
        let port = try await startReceiver()
        send([try file("x.bin", bytes: 1_000)], port: port, rename: { _ in "../\u{200D}../\u{200D}etc/passwd" })
        let saved = await log.wait { if case .finished(_, _, let files, _, _) = $0 { files } else { nil } }
        let target = try #require(saved?.first)
        #expect(target.deletingLastPathComponent().standardizedFileURL == inbox.standardizedFileURL)
        #expect(target.lastPathComponent == "Quick Share file") // the unsafe name is discarded entirely
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("etc").path))
    }

    @Test("An existing file with the same name is never overwritten")
    func noOverwrite() async throws {
        let port = try await startReceiver()
        try Data("original".utf8).write(to: inbox.appendingPathComponent("notes.txt"))
        send([try file("notes.txt", bytes: 500)], port: port)
        let saved = await log.wait { if case .finished(_, _, let files, _, _) = $0 { files } else { nil } }
        #expect(saved?.first?.lastPathComponent == "notes (2).txt")
        #expect(try String(contentsOf: inbox.appendingPathComponent("notes.txt"), encoding: .utf8) == "original")
    }

    @Test("A link is delivered to the app, never opened automatically")
    func link() async throws {
        let port = try await startReceiver()
        send([URL(string: "https://example.com/page")!], port: port)
        let link = await log.wait { if case .finished(_, _, _, let link, _) = $0 { link } else { nil } }
        #expect(link == URL(string: "https://example.com/page"))
    }

    @Test("Key encoding helpers round-trip 32-byte coordinates")
    func keyEncoding() {
        let high = Data([0x80] + Array(repeating: 1, count: 31))
        #expect(NearbyConnection.signedBytes(high).count == 33)
        #expect(NearbyConnection.fixed32(NearbyConnection.signedBytes(high)) == high)
        #expect(NearbyConnection.fixed32(Data([1, 2])) == Data(repeating: 0, count: 30) + Data([1, 2]))
        #expect(NearbyConnection.fixed32(Data([9] + Array(repeating: 0, count: 32))) == nil)
    }

    @Test("Device names are cleaned before display")
    func names() {
        #expect(QuickShareReceiver.displaySafe("Pixel\u{202E}9\u{0007}") == "Pixel9")
        #expect(QuickShareReceiver.displaySafe("\u{200B}") == "Android device")
    }
}
