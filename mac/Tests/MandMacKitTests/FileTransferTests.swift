import CryptoKit
import Foundation
import MandCore
@testable import MandMacKit
import Testing

/// Two FileTransferService instances wired back-to-back, so both sending and receiving run for real.
/// `tamper` lets a test corrupt or drop messages in flight.
final class Loopback: @unchecked Sendable {
    let lock = NSLock()
    var isUp = true
    var tamper: (@Sendable (Message) -> Message?)?
    private(set) var log: [Message] = []
    var sender: FileTransferService!
    var receiver: FileTransferService!
    let senderItems = Recorder<[FileTransferService.Item]>()
    let receiverItems = Recorder<[FileTransferService.Item]>()

    init(senderFolder: URL, receiverFolder: URL) {
        let partials = receiverFolder.deletingLastPathComponent().appendingPathComponent("partials")
        sender = FileTransferService(destination: { senderFolder }, partialFolder: partials.appendingPathComponent("s"), send: { [unowned self] message, done in
            self.deliver(message, to: { self.receiver }, done: done)
        }, onChange: { [unowned self] in self.senderItems.append($0) })
        receiver = FileTransferService(destination: { receiverFolder }, partialFolder: partials.appendingPathComponent("r"), send: { [unowned self] message, done in
            self.deliver(message, to: { self.sender }, done: done)
        }, onChange: { [unowned self] in self.receiverItems.append($0) })
        sender.connectionChanged(connected: true)
        receiver.connectionChanged(connected: true)
    }

    private func deliver(_ message: Message, to target: @escaping () -> FileTransferService,
                         done: (@Sendable (Bool) -> Void)?) {
        let (up, change) = lock.withLock { (isUp, tamper) }
        guard up else { done?(false); return }
        guard let message = change.map({ $0(message) }) ?? message else { done?(true); return }
        lock.withLock { log.append(message) }
        target().handle(message)
        done?(true)
    }

    var messages: [Message] { lock.withLock { log } }

    func setUp(_ up: Bool) {
        lock.withLock { isUp = up }
        sender.connectionChanged(connected: up)
        receiver.connectionChanged(connected: up)
    }

    /// Waits until the receiver reports a finished item and returns it.
    func finished(timeout: TimeInterval = 15) async -> FileTransferService.Item? {
        await receiverItems.wait(timeout: timeout) { items in items.first { $0.isFinished } }
    }
}

@Suite("File transfer", .serialized)
final class FileTransferTests {
    let root: URL
    let inbox: URL
    let outbox: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("mand-files-\(UUID().uuidString)")
        inbox = root.appendingPathComponent("inbox")
        outbox = root.appendingPathComponent("outbox")
        try FileManager.default.createDirectory(at: outbox, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: root) }

    func makeFile(_ name: String, bytes: Int) throws -> URL {
        let url = outbox.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var generator = SystemRandomNumberGenerator()
        let data = Data((0..<bytes).map { _ in UInt8.random(in: 0...255, using: &generator) })
        try data.write(to: url)
        return url
    }

    @Test("A file arrives intact under the same name")
    func basicTransfer() async throws {
        let link = Loopback(senderFolder: outbox, receiverFolder: inbox)
        let source = try makeFile("report.pdf", bytes: 1_000_000) // several chunks, more than one window
        link.sender.send(urls: [source])
        let item = await link.finished()
        #expect(item?.state == .done)
        #expect(try Data(contentsOf: inbox.appendingPathComponent("report.pdf")) == Data(contentsOf: source))
        let senderDone = await link.senderItems.wait { $0.first { $0.isFinished } }
        #expect(senderDone?.state == .done)
    }

    @Test("Empty files and folders with structure transfer correctly")
    func foldersAndEmptyFiles() async throws {
        let link = Loopback(senderFolder: outbox, receiverFolder: inbox)
        _ = try makeFile("Album/one.jpg", bytes: 2_000)
        _ = try makeFile("Album/nested/two.jpg", bytes: 0)
        link.sender.send(urls: [outbox.appendingPathComponent("Album")])
        let both = await link.receiverItems.wait { items in items.filter(\.isFinished).count == 2 ? items : nil }
        #expect(both?.allSatisfy { $0.state == .done } == true)
        #expect(FileManager.default.fileExists(atPath: inbox.appendingPathComponent("Album/one.jpg").path))
        #expect(FileManager.default.fileExists(atPath: inbox.appendingPathComponent("Album/nested/two.jpg").path))
    }

    @Test("A path-traversal name is rejected and nothing is written outside the folder")
    func traversalRejected() async throws {
        let link = Loopback(senderFolder: outbox, receiverFolder: inbox)
        let source = try makeFile("innocent.txt", bytes: 100)
        link.tamper = { message in
            guard case .fileOffer(let offer) = message else { return message }
            return .fileOffer(FileOffer(tid: offer.tid, name: "../../escaped.txt", size: offer.size, sha256: offer.sha256))
        }
        link.sender.send(urls: [source])
        let failed = await link.senderItems.wait { $0.first { $0.isFinished } }
        #expect(failed?.state == .failed(FileTransferService.describeReject("invalid_name")))
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("escaped.txt").path))
        #expect(!FileManager.default.fileExists(atPath: inbox.deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("escaped.txt").path))
    }

    @Test("Corrupted data is detected by the checksum and not saved")
    func integrityFailure() async throws {
        let link = Loopback(senderFolder: outbox, receiverFolder: inbox)
        let source = try makeFile("photo.jpg", bytes: 50_000)
        link.tamper = { message in
            guard case .fileChunk(let tid, let offset, var data) = message else { return message }
            data[0] ^= 0xFF
            return .fileChunk(tid: tid, offset: offset, data: data)
        }
        link.sender.send(urls: [source])
        let item = await link.finished()
        guard case .failed = item?.state else { Issue.record("expected failure, got \(String(describing: item?.state))"); return }
        #expect(!FileManager.default.fileExists(atPath: inbox.appendingPathComponent("photo.jpg").path))
        let senderItem = await link.senderItems.wait { $0.first { $0.isFinished } }
        guard case .failed = senderItem?.state else { Issue.record("sender should report failure"); return }
    }

    @Test("An interrupted transfer resumes where it stopped after reconnecting")
    func resumeAfterInterruption() async throws {
        let link = Loopback(senderFolder: outbox, receiverFolder: inbox)
        let source = try makeFile("video.mov", bytes: 3_000_000)
        // Drop the link once about 1 MB has been acknowledged.
        link.tamper = { [unowned link] message in
            if case .fileAck(_, let received) = message, received >= 1_000_000 {
                link.tamper = nil
                DispatchQueue.global().async { link.setUp(false) }
            }
            return message
        }
        link.sender.send(urls: [source])
        let interrupted = await link.receiverItems.wait { $0.first { $0.state == .interrupted } }
        #expect(interrupted != nil)

        link.setUp(true)
        let item = await link.finished(timeout: 20)
        #expect(item?.state == .done)
        #expect(try Data(contentsOf: inbox.appendingPathComponent("video.mov")) == Data(contentsOf: source))
        let resumeOffsets = link.messages.compactMap { message -> Int64? in
            if case .fileAccept(_, let offset) = message { offset } else { nil }
        }
        #expect(resumeOffsets.count == 2)
        #expect((resumeOffsets.last ?? 0) > 0) // second accept continued from the partial file
    }

    @Test("Identical files aren't duplicated; different files with the same name aren't overwritten")
    func noDuplicatesNoOverwrites() async throws {
        let link = Loopback(senderFolder: outbox, receiverFolder: inbox)
        let source = try makeFile("notes.txt", bytes: 5_000)
        link.sender.send(urls: [source])
        _ = await link.finished()

        // Same content again → "already there", no copy.
        link.sender.send(urls: [source])
        let second = await link.receiverItems.wait { $0.first { $0.state == .alreadyThere } }
        #expect(second != nil)

        // Different content, same name → saved as "notes (2).txt", original untouched.
        let original = try Data(contentsOf: inbox.appendingPathComponent("notes.txt"))
        let changed = try makeFile("notes.txt", bytes: 6_000)
        link.sender.send(urls: [changed])
        let third = await link.receiverItems.wait { items in items.filter { $0.state == .done }.count == 2 ? items : nil }
        #expect(third != nil)
        #expect(try Data(contentsOf: inbox.appendingPathComponent("notes.txt")) == original)
        #expect(try Data(contentsOf: inbox.appendingPathComponent("notes (2).txt")) == Data(contentsOf: changed))
    }

    @Test("Out-of-order chunks cancel the transfer")
    func outOfOrderRejected() async throws {
        let link = Loopback(senderFolder: outbox, receiverFolder: inbox)
        let source = try makeFile("a.bin", bytes: 500_000)
        link.tamper = { message in
            guard case .fileChunk(let tid, let offset, let data) = message, offset > 0 else { return message }
            return .fileChunk(tid: tid, offset: offset + 1, data: data)
        }
        link.sender.send(urls: [source])
        let item = await link.finished()
        guard case .failed = item?.state else { Issue.record("expected failure"); return }
        #expect(!FileManager.default.fileExists(atPath: inbox.appendingPathComponent("a.bin").path))
    }
}
