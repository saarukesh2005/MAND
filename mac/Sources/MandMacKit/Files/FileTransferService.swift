import CryptoKit
import Foundation
import MandCore

/// Two-way file transfer over the paired connection (protocol §3a, `file.v1`).
/// All state lives on `queue`. Received names are never trusted: they go through `SafeFileName`.
public final class FileTransferService: @unchecked Sendable {
    public enum Direction: Sendable, Equatable, Codable { case incoming, outgoing }

    public enum State: Sendable, Equatable, Codable {
        case preparing          // outgoing: hashing the file
        case waiting            // queued until the phone is connected / earlier transfers finish
        case offered            // outgoing: waiting for the phone to accept
        case active
        case interrupted        // connection lost; resumes automatically on reconnect
        case done
        case alreadyThere       // an identical file already existed; nothing copied
        case failed(String)
        case cancelled
    }

    public struct Item: Identifiable, Sendable, Equatable, Codable {
        public let id: String
        public let name: String
        public let direction: Direction
        public let size: Int64
        public var transferred: Int64
        public var bytesPerSecond: Double
        public var state: State
        public var savedURL: URL?

        public var isFinished: Bool {
            switch state {
            case .done, .alreadyThere, .failed, .cancelled: true
            default: false
            }
        }
    }

    public static let windowChunks: Int64 = 8
    public static let maxConcurrentIncoming = 4
    static let progressInterval: TimeInterval = 0.2
    static let freeSpaceMargin: Int64 = 200 * 1_048_576

    public typealias Sender = @Sendable (Message, (@Sendable (Bool) -> Void)?) -> Void

    private let queue = DispatchQueue(label: "dev.mand.mac.files")
    private let sendMessage: Sender
    private let destination: @Sendable () -> URL
    /// Half-received files live here (not in the visible download folder) until verified.
    private let partialFolder: URL
    private let onChange: @Sendable ([Item]) -> Void

    private var items: [Item] = []
    private var incoming: [String: Incoming] = [:]
    private var outgoing: [String: Outgoing] = [:]
    private var isConnected = false
    private var lastPublish = Date.distantPast
    private var publishScheduled = false

    public init(destination: @escaping @Sendable () -> URL,
                partialFolder: URL = FileTransferService.defaultPartialFolder,
                send: @escaping Sender,
                onChange: @escaping @Sendable ([Item]) -> Void) {
        self.destination = destination
        self.partialFolder = partialFolder
        self.sendMessage = send
        self.onChange = onChange
    }

    // MARK: - Public API (any thread)

    public func handle(_ message: Message) {
        queue.async { self.receive(message) }
    }

    /// Call with `true` when a phone that supports `file.v1` becomes ready, `false` when it goes away.
    public func connectionChanged(connected: Bool) {
        queue.async {
            self.isConnected = connected
            connected ? self.resumeAfterReconnect() : self.interruptAll()
        }
    }

    /// Queues files and folders for sending to the phone (folders are sent with their structure).
    public func send(urls: [URL]) {
        queue.async {
            for (url, name) in Self.expand(urls) { self.enqueueOutgoing(url: url, name: name) }
            self.publish(force: true)
        }
    }

    public func cancel(id: String) {
        queue.async {
            if let transfer = self.outgoing[id] {
                transfer.handle?.closeFile()
                self.outgoing[id] = nil
                self.sendMessage(.fileCancel(tid: id, reason: "user"), nil)
                self.update(id) { $0.state = .cancelled }
                self.pump()
            } else if let transfer = self.incoming[id] {
                transfer.handle.closeFile()
                try? FileManager.default.removeItem(at: transfer.partURL)
                self.incoming[id] = nil
                self.sendMessage(.fileCancel(tid: id, reason: "user"), nil)
                self.update(id) { $0.state = .cancelled }
            }
            self.publish(force: true)
        }
    }

    /// Re-queues a failed or cancelled outgoing transfer.
    public func retry(id: String) {
        queue.async {
            guard let item = self.items.first(where: { $0.id == id }), item.direction == .outgoing,
                  let url = self.retryURLs[id] else { return }
            self.items.removeAll { $0.id == id }
            self.enqueueOutgoing(url: url, name: item.name)
            self.publish(force: true)
        }
    }

    public func clearFinished() {
        queue.async {
            self.items.removeAll(where: \.isFinished)
            self.publish(force: true)
        }
    }

    /// Deletes leftover partial downloads older than `maxAge` (default 7 days).
    public func cleanUpPartials(maxAge: TimeInterval = 7 * 86_400) {
        queue.async {
            let folder = self.partialFolder
            let files = (try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            for file in files {
                let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                if let modified, Date().timeIntervalSince(modified) > maxAge { try? FileManager.default.removeItem(at: file) }
            }
        }
    }

    // MARK: - Incoming (phone → Mac)

    private final class Incoming {
        let offer: FileOffer
        let components: [String]
        let partURL: URL
        let handle: FileHandle
        var hasher: SHA256
        var received: Int64
        var meter: SpeedMeter

        init(offer: FileOffer, components: [String], partURL: URL, handle: FileHandle, hasher: SHA256, received: Int64) {
            self.offer = offer
            self.components = components
            self.partURL = partURL
            self.handle = handle
            self.hasher = hasher
            self.received = received
            meter = SpeedMeter(start: received)
        }
    }

    private func receive(_ message: Message) {
        switch message {
        case .fileOffer(let offer): receiveOffer(offer)
        case .fileChunk(let tid, let offset, let data): receiveChunk(tid: tid, offset: offset, data: data)
        case .fileDone(let tid): receiveDone(tid: tid)
        case .fileAccept(let tid, let offset): outgoingAccepted(tid: tid, offset: offset)
        case .fileReject(let tid, let reason): outgoingRejected(tid: tid, reason: reason)
        case .fileAck(let tid, let received): outgoingAcked(tid: tid, received: received)
        case .fileResult(let tid, let ok, let reason): outgoingResult(tid: tid, ok: ok, reason: reason)
        case .fileCancel(let tid, _): peerCancelled(tid: tid)
        default: break
        }
        publish()
    }

    private func receiveOffer(_ offer: FileOffer) {
        guard incoming[offer.tid] == nil else { return }
        guard incoming.count < Self.maxConcurrentIncoming else { return reject(offer, "busy") }
        guard let components = try? SafeFileName.components(of: offer.name) else { return reject(offer, "invalid_name") }

        let fm = FileManager.default
        let root = destination()
        // Must stay inside the download folder even if something in it is a symlink.
        guard let existing = SafeFileName.contained(components, in: root) else { return reject(offer, "invalid_name") }
        let folder = existing.deletingLastPathComponent()
        let partFolder = partialFolder
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try fm.createDirectory(at: partFolder, withIntermediateDirectories: true)
        } catch {
            return reject(offer, "no_space")
        }

        // Identical file already there? Don't make a duplicate.
        if Self.fileSize(existing) == offer.size, Self.sha256Hex(of: existing) == offer.sha256 {
            sendMessage(.fileReject(tid: offer.tid, reason: "already_exists"), nil)
            append(Item(id: offer.tid, name: components.joined(separator: "/"), direction: .incoming,
                        size: offer.size, transferred: offer.size, bytesPerSecond: 0, state: .alreadyThere,
                        savedURL: existing))
            return
        }

        // Resume a partial download of the same content if we have one.
        let partURL = partFolder.appendingPathComponent("\(offer.sha256)-\(offer.size).part")
        // Two transfers of the same content at once would share (and corrupt) one partial file.
        guard !incoming.values.contains(where: { $0.partURL == partURL }) else { return reject(offer, "busy") }
        var already = Self.fileSize(partURL) ?? 0
        if already > offer.size {
            try? fm.removeItem(at: partURL)
            already = 0
        }
        // Count space already promised to other incoming transfers, not just this one.
        let reserved = incoming.values.reduce(Int64(0)) { $0 + ($1.offer.size - $1.received) }
        if Self.availableSpace(at: root) - Self.freeSpaceMargin < offer.size - already + reserved {
            return reject(offer, "no_space")
        }
        if !fm.fileExists(atPath: partURL.path) { fm.createFile(atPath: partURL.path, contents: nil) }

        guard let handle = try? FileHandle(forUpdating: partURL) else { return reject(offer, "no_space") }
        var hasher = SHA256()
        if already > 0, let reader = try? FileHandle(forReadingFrom: partURL) {
            var remaining = already
            while remaining > 0, let block = try? reader.read(upToCount: Int(min(remaining, 1_048_576))), !block.isEmpty {
                hasher.update(data: block)
                remaining -= Int64(block.count)
            }
            try? reader.close()
            already -= remaining
        }
        try? handle.truncate(atOffset: UInt64(already))
        try? handle.seekToEnd()

        incoming[offer.tid] = Incoming(offer: offer, components: components, partURL: partURL,
                                       handle: handle, hasher: hasher, received: already)
        let name = components.joined(separator: "/")
        if let index = items.firstIndex(where: { $0.direction == .incoming && $0.name == name && $0.state == .interrupted }) {
            items.remove(at: index)
        }
        append(Item(id: offer.tid, name: name, direction: .incoming, size: offer.size,
                    transferred: already, bytesPerSecond: 0, state: .active, savedURL: nil))
        sendMessage(.fileAccept(tid: offer.tid, offset: already), nil)
        if offer.size == 0 { receiveDoneIfComplete(offer.tid) }
    }

    private func reject(_ offer: FileOffer, _ reason: String) {
        sendMessage(.fileReject(tid: offer.tid, reason: reason), nil)
    }

    private func receiveChunk(tid: String, offset: Int64, data: Data) {
        guard let transfer = incoming[tid] else { return }
        guard offset == transfer.received, transfer.received + Int64(data.count) <= transfer.offer.size else {
            return failIncoming(tid, reason: "out_of_order", notify: true)
        }
        do {
            try transfer.handle.write(contentsOf: data)
        } catch {
            return failIncoming(tid, reason: "no_space", notify: true)
        }
        transfer.hasher.update(data: data)
        transfer.received += Int64(data.count)
        let speed = transfer.meter.record(transfer.received)
        sendMessage(.fileAck(tid: tid, received: transfer.received), nil)
        update(tid) {
            $0.transferred = transfer.received
            $0.bytesPerSecond = speed
        }
    }

    private func receiveDone(tid: String) { receiveDoneIfComplete(tid) }

    private func receiveDoneIfComplete(_ tid: String) {
        guard let transfer = incoming[tid] else { return }
        incoming[tid] = nil
        try? transfer.handle.close()
        let digest = transfer.hasher.finalize().map { String(format: "%02x", $0) }.joined()
        guard transfer.received == transfer.offer.size, digest == transfer.offer.sha256 else {
            try? FileManager.default.removeItem(at: transfer.partURL)
            sendMessage(.fileResult(tid: tid, ok: false, reason: "integrity"), nil)
            update(tid) { $0.state = .failed("The file was damaged in transit and was not saved.") }
            return
        }
        // Re-check containment and re-create folders: the download folder may have changed mid-transfer.
        guard let target = SafeFileName.contained(transfer.components, in: destination()),
              (try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)) != nil else {
            try? FileManager.default.removeItem(at: transfer.partURL)
            sendMessage(.fileResult(tid: tid, ok: false, reason: "invalid_name"), nil)
            update(tid) { $0.state = .failed("Couldn’t save the file in the download folder.") }
            return
        }
        let folder = target.deletingLastPathComponent()
        let finalName = SafeFileName.uniqueName(transfer.components.last!) {
            FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path)
        }
        let finalURL = folder.appendingPathComponent(finalName)
        do {
            try FileManager.default.moveItem(at: transfer.partURL, to: finalURL)
            sendMessage(.fileResult(tid: tid, ok: true, reason: nil), nil)
            update(tid) {
                $0.state = .done
                $0.transferred = transfer.offer.size
                $0.savedURL = finalURL
            }
        } catch {
            sendMessage(.fileResult(tid: tid, ok: false, reason: "no_space"), nil)
            update(tid) { $0.state = .failed("Couldn’t save the file: \(error.localizedDescription)") }
        }
    }

    private func failIncoming(_ tid: String, reason: String, notify: Bool) {
        guard let transfer = incoming.removeValue(forKey: tid) else { return }
        try? transfer.handle.close()
        try? FileManager.default.removeItem(at: transfer.partURL)
        if notify { sendMessage(.fileCancel(tid: tid, reason: reason), nil) }
        update(tid) { $0.state = .failed("Transfer stopped (\(reason)).") }
    }

    private func peerCancelled(tid: String) {
        if let transfer = incoming.removeValue(forKey: tid) {
            try? transfer.handle.close()
            try? FileManager.default.removeItem(at: transfer.partURL)
            update(tid) { $0.state = .cancelled }
        } else if let transfer = outgoing.removeValue(forKey: tid) {
            transfer.handle?.closeFile()
            update(tid) { $0.state = .cancelled }
            pump()
        }
    }

    // MARK: - Outgoing (Mac → phone)

    private final class Outgoing {
        let url: URL
        let name: String
        var size: Int64 = 0
        var sha256 = ""
        var tid: String
        var handle: FileHandle?
        var sent: Int64 = 0
        var acked: Int64 = 0
        var doneSent = false
        var meter = SpeedMeter(start: 0)

        init(url: URL, name: String, tid: String) {
            self.url = url
            self.name = name
            self.tid = tid
        }
    }

    private var outgoingOrder: [String] = []
    private var retryURLs: [String: URL] = [:]

    private func enqueueOutgoing(url: URL, name: String) {
        let tid = UUID().uuidString
        let transfer = Outgoing(url: url, name: name, tid: tid)
        let size = Self.fileSize(url) ?? 0
        transfer.size = size
        outgoing[tid] = transfer
        outgoingOrder.append(tid)
        retryURLs[tid] = url
        append(Item(id: tid, name: name, direction: .outgoing, size: size, transferred: 0,
                    bytesPerSecond: 0, state: .preparing, savedURL: url))
        // Hash on a background queue, then come back to `queue`.
        DispatchQueue.global(qos: .utility).async {
            let digest = Self.sha256Hex(of: url)
            self.queue.async {
                guard let transfer = self.outgoing[tid] else { return }
                guard let digest, size <= Message.maxFileSize else {
                    self.outgoing[tid] = nil
                    self.update(tid) { $0.state = .failed("Couldn’t read this file.") }
                    self.publish(force: true)
                    return
                }
                transfer.sha256 = digest
                self.update(tid) { $0.state = .waiting }
                self.pump()
                self.publish(force: true)
            }
        }
    }

    /// Starts the next waiting outgoing transfer (one at a time keeps the link responsive).
    private func pump() {
        guard isConnected else { return }
        let busy = outgoing.values.contains { transfer in
            items.first(where: { $0.id == transfer.tid }).map { $0.state == .offered || $0.state == .active } ?? false
        }
        guard !busy else { return }
        outgoingOrder.removeAll { outgoing[$0] == nil }
        guard let tid = outgoingOrder.first(where: { id in items.first { $0.id == id }?.state == .waiting }),
              let transfer = outgoing[tid] else { return }
        update(tid) { $0.state = .offered }
        sendMessage(.fileOffer(FileOffer(tid: tid, name: transfer.name, size: transfer.size, sha256: transfer.sha256)), nil)
    }

    private func outgoingAccepted(tid: String, offset: Int64) {
        // Only the first accept for an offered transfer counts (a repeat would leak the open file).
        guard let transfer = outgoing[tid], offset <= transfer.size,
              items.first(where: { $0.id == tid })?.state == .offered else { return }
        guard let handle = try? FileHandle(forReadingFrom: transfer.url) else {
            outgoing[tid] = nil
            sendMessage(.fileCancel(tid: tid, reason: "unreadable"), nil)
            update(tid) { $0.state = .failed("Couldn’t read this file.") }
            return pump()
        }
        try? handle.seek(toOffset: UInt64(offset))
        transfer.handle = handle
        transfer.sent = offset
        transfer.acked = offset
        transfer.meter = SpeedMeter(start: offset)
        update(tid) {
            $0.state = .active
            $0.transferred = offset
        }
        sendMore(transfer)
    }

    private func sendMore(_ transfer: Outgoing) {
        guard isConnected, let handle = transfer.handle else { return }
        let chunk = Int64(Message.maxFileChunkBytes)
        while transfer.sent < transfer.size, transfer.sent - transfer.acked < Self.windowChunks * chunk {
            guard let data = try? handle.read(upToCount: Int(min(chunk, transfer.size - transfer.sent))), !data.isEmpty else {
                outgoing[transfer.tid] = nil
                sendMessage(.fileCancel(tid: transfer.tid, reason: "unreadable"), nil)
                update(transfer.tid) { $0.state = .failed("The file changed or couldn’t be read while sending.") }
                return pump()
            }
            sendMessage(.fileChunk(tid: transfer.tid, offset: transfer.sent, data: data), nil)
            transfer.sent += Int64(data.count)
        }
        if transfer.sent == transfer.size, !transfer.doneSent {
            transfer.doneSent = true
            sendMessage(.fileDone(tid: transfer.tid), nil)
        }
    }

    private func outgoingAcked(tid: String, received: Int64) {
        guard let transfer = outgoing[tid], received >= transfer.acked, received <= transfer.sent else { return }
        transfer.acked = received
        let speed = transfer.meter.record(received)
        update(tid) {
            $0.transferred = received
            $0.bytesPerSecond = speed
        }
        sendMore(transfer)
    }

    private func outgoingRejected(tid: String, reason: String) {
        guard let transfer = outgoing.removeValue(forKey: tid) else { return }
        transfer.handle?.closeFile()
        update(tid) {
            $0.state = reason == "already_exists" ? .alreadyThere : .failed(Self.describeReject(reason))
        }
        pump()
    }

    private func outgoingResult(tid: String, ok: Bool, reason: String?) {
        guard let transfer = outgoing.removeValue(forKey: tid) else { return }
        transfer.handle?.closeFile()
        update(tid) {
            if ok {
                $0.state = .done
                $0.transferred = $0.size
            } else {
                $0.state = .failed(reason == "integrity" ? "The phone found the file damaged in transit. Try again."
                                                         : "The phone couldn’t save the file (\(reason ?? "error")).")
            }
        }
        pump()
    }

    // MARK: - Connection changes

    private func interruptAll() {
        for (tid, transfer) in incoming {
            try? transfer.handle.close()
            update(tid) { $0.state = .interrupted } // partial file kept for resuming
        }
        incoming.removeAll()
        for transfer in outgoing.values {
            transfer.handle?.closeFile()
            transfer.handle = nil
            transfer.doneSent = false
            update(transfer.tid) { item in
                if item.state == .offered || item.state == .active { item.state = .interrupted }
            }
        }
        publish(force: true)
    }

    private func resumeAfterReconnect() {
        for transfer in outgoing.values {
            update(transfer.tid) { if $0.state == .interrupted { $0.state = .waiting } }
        }
        pump()
        publish(force: true)
    }

    // MARK: - Helpers

    public static let maxItems = 200

    /// Adds to the list, dropping the oldest finished items beyond `maxItems`.
    private func append(_ item: Item) {
        items.append(item)
        while items.count > Self.maxItems, let index = items.firstIndex(where: \.isFinished) {
            retryURLs[items[index].id] = nil
            items.remove(at: index)
        }
    }

    private func update(_ id: String, _ change: (inout Item) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
    }

    private func publish(force: Bool = false) {
        let now = Date()
        if force || now.timeIntervalSince(lastPublish) >= Self.progressInterval {
            lastPublish = now
            onChange(items)
        } else if !publishScheduled {
            publishScheduled = true
            queue.asyncAfter(deadline: .now() + Self.progressInterval) {
                self.publishScheduled = false
                self.publish(force: true)
            }
        }
    }

    static func describeReject(_ reason: String) -> String {
        switch reason {
        case "too_large": "The file is too large for the phone."
        case "no_space": "The phone doesn’t have enough free space."
        case "invalid_name": "The phone refused the file name."
        case "busy": "The phone is busy with other transfers. Try again shortly."
        case "disabled": "File receiving is turned off on the phone."
        default: "The phone declined the file (\(reason))."
        }
    }

    /// Expands folders into their regular files, keeping the folder structure in the relative name.
    static func expand(_ urls: [URL]) -> [(URL, String)] {
        var result: [(URL, String)] = []
        for url in urls {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if !isDirectory.boolValue {
                result.append((url, url.lastPathComponent))
                continue
            }
            let base = url.deletingLastPathComponent().standardizedFileURL.path
            let enumerator = FileManager.default.enumerator(
                at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants])
            while let file = enumerator?.nextObject() as? URL {
                guard (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
                let relative = String(file.standardizedFileURL.path.dropFirst(base.count)).trimmingCharacters(in: ["/"])
                result.append((file, relative))
            }
        }
        return result
    }

    /// ~/Library/Application Support/M’AND/Partial — not a privacy-protected folder.
    public static var defaultPartialFolder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("M’AND/Partial", isDirectory: true)
    }

    static func fileSize(_ url: URL) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
    }

    static func sha256Hex(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let block = try? handle.read(upToCount: 1_048_576), !block.isEmpty { hasher.update(data: block) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func availableSpace(at url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? .max
    }
}

/// Rolling transfer-speed estimate over roughly the last second.
struct SpeedMeter {
    private var samples: [(Date, Int64)]

    init(start: Int64) { samples = [(Date(), start)] }

    mutating func record(_ total: Int64) -> Double {
        let now = Date()
        samples.append((now, total))
        samples.removeAll { now.timeIntervalSince($0.0) > 1.5 }
        guard let first = samples.first, samples.count > 1 else { return 0 }
        let elapsed = now.timeIntervalSince(first.0)
        return elapsed > 0 ? Double(total - first.1) / elapsed : 0
    }
}
