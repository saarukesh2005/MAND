import Foundation

/// Optional capabilities announced in `hello.features` (protocol §3a).
public enum Feature {
    public static let files = "file.v1"
    public static let clipboard = "clipboard.v1"
    public static let device = "device.v1"
    public static let notifications = "notifications.v1"
    public static let calls = "calls.v1"
    public static let tap = "tap.v1"
    public static let find = "find.v1"
    public static let link = "link.v1"
    public static let all: [String] = [files, clipboard, device, notifications, calls, tap, find, link]
}

/// The `hello` body (protocol §3).
public struct Hello: Equatable, Sendable {
    public enum Platform: String, Sendable { case mac, android }

    public let name: String
    public let platform: Platform
    public let versions: ClosedRange<Int>
    public let app: String
    public let features: [String]

    public init(name: String, platform: Platform, versions: ClosedRange<Int>, app: String, features: [String] = []) {
        self.name = name
        self.platform = platform
        self.versions = versions
        self.app = app
        self.features = features
    }
}

/// `file.offer` body (protocol §3a).
public struct FileOffer: Equatable, Sendable {
    public let tid: String
    public let name: String
    public let size: Int64
    public let sha256: String

    public init(tid: String, name: String, size: Int64, sha256: String) {
        self.tid = tid
        self.name = name
        self.size = size
        self.sha256 = sha256
    }
}

/// `notification.posted` body (protocol §3a).
public struct PhoneNotification: Equatable, Sendable, Identifiable {
    public let key: String
    public let app: String
    public let appName: String
    public let title: String?
    public let text: String?
    public let time: Int64

    public var id: String { key }

    public init(key: String, app: String, appName: String, title: String?, text: String?, time: Int64) {
        self.key = key
        self.app = app
        self.appName = appName
        self.title = title
        self.text = text
        self.time = time
    }
}

/// `device.info` body (protocol §3a): what the phone is, and its free storage.
public struct DeviceInfo: Equatable, Sendable {
    public let model: String
    public let os: String
    public let storageFree: Int64
    public let storageTotal: Int64

    public init(model: String, os: String, storageFree: Int64, storageTotal: Int64) {
        self.model = model
        self.os = os
        self.storageFree = storageFree
        self.storageTotal = storageTotal
    }
}

/// Rules for `link.open` URLs: only web links, so a paired device can never open apps, files or scripts.
public enum LinkRules {
    public static let maxURLBytes = 2_048
    public static let maxTitleBytes = 256

    public static func isValid(_ url: String) -> Bool {
        guard !url.isEmpty, url.utf8.count <= maxURLBytes,
              !url.unicodeScalars.contains(where: { $0.value <= 0x20 || $0.value == 0x7f }) else { return false }
        let lower = url.lowercased()
        let rest: Substring
        if lower.hasPrefix("https://") { rest = lower.dropFirst(8) }
        else if lower.hasPrefix("http://") { rest = lower.dropFirst(7) }
        else { return false }
        guard let host = rest.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).first else { return false }
        return !host.isEmpty && !host.hasPrefix("@")
    }
}

/// Every v1 message. Unknown types decode to `.unknown` and must be ignored.
public enum Message: Equatable, Sendable {
    case hello(Hello)
    case pairRequest(proof: String)
    case pairResult(accepted: Bool, reason: String?)
    case sessionReady
    case ping
    case pong(ref: String)
    case text(String)
    case bye(reason: String)
    case error(code: String, message: String?)
    case fileOffer(FileOffer)
    case fileAccept(tid: String, offset: Int64)
    case fileReject(tid: String, reason: String)
    case fileChunk(tid: String, offset: Int64, data: Data)
    case fileAck(tid: String, received: Int64)
    case fileDone(tid: String)
    case fileResult(tid: String, ok: Bool, reason: String?)
    case fileCancel(tid: String, reason: String)
    case clipboardText(String)
    case deviceStatus(battery: Int, charging: Bool)
    case notificationPosted(PhoneNotification)
    case notificationRemoved(key: String)
    case notificationDismiss(key: String)
    case callState(CallState, caller: String?)
    case callAction(CallAction)
    case tapKnock
    case tapGrab(round: Int64, dark: Bool)
    case tapDecline(round: Int64, why: String)
    case tapLight(round: Int64, on: Bool)
    case tapSeen(round: Int64)
    case tapResult(round: Int64, ok: Bool, why: String?)
    case deviceInfo(DeviceInfo)
    case findRing
    case findStop
    case findState(ringing: Bool)
    case linkOpen(url: String, title: String?)
    case unknown(type: String)

    public enum CallState: String, Sendable { case ringing, active, idle }
    public enum CallAction: String, Sendable { case answer, decline }

    public static let maxTextBytes = 16_384
    public static let maxNameBytes = 128
    public static let maxClipboardBytes = 262_144
    public static let maxFileChunkBytes = 196_608
    public static let maxFileSize: Int64 = 1 << 40
    public static let maxStorageBytes: Int64 = 1 << 50

    public var type: String {
        switch self {
        case .hello: "hello"
        case .pairRequest: "pair.request"
        case .pairResult: "pair.result"
        case .sessionReady: "session.ready"
        case .ping: "ping"
        case .pong: "pong"
        case .text: "text"
        case .bye: "bye"
        case .error: "error"
        case .fileOffer: "file.offer"
        case .fileAccept: "file.accept"
        case .fileReject: "file.reject"
        case .fileChunk: "file.chunk"
        case .fileAck: "file.ack"
        case .fileDone: "file.done"
        case .fileResult: "file.result"
        case .fileCancel: "file.cancel"
        case .clipboardText: "clipboard.text"
        case .deviceStatus: "device.status"
        case .notificationPosted: "notification.posted"
        case .notificationRemoved: "notification.removed"
        case .notificationDismiss: "notification.dismiss"
        case .callState: "call.state"
        case .callAction: "call.action"
        case .tapKnock: "tap.knock"
        case .tapGrab: "tap.grab"
        case .tapDecline: "tap.decline"
        case .tapLight: "tap.light"
        case .tapSeen: "tap.seen"
        case .tapResult: "tap.result"
        case .deviceInfo: "device.info"
        case .findRing: "find.ring"
        case .findStop: "find.stop"
        case .findState: "find.state"
        case .linkOpen: "link.open"
        case .unknown(let type): type
        }
    }

    /// The feature a message belongs to, or nil for core protocol messages.
    public var feature: String? {
        switch self {
        case .fileOffer, .fileAccept, .fileReject, .fileChunk, .fileAck, .fileDone, .fileResult, .fileCancel:
            Feature.files
        case .clipboardText: Feature.clipboard
        case .deviceStatus, .deviceInfo: Feature.device
        case .findRing, .findStop, .findState: Feature.find
        case .linkOpen: Feature.link
        case .notificationPosted, .notificationRemoved, .notificationDismiss: Feature.notifications
        case .callState, .callAction: Feature.calls
        case .tapKnock, .tapGrab, .tapDecline, .tapLight, .tapSeen, .tapResult: Feature.tap
        default: nil
        }
    }
}

/// A validated message plus its envelope metadata.
public struct Envelope: Equatable, Sendable {
    public let version: Int
    public let id: String
    public let timestampMillis: Int64
    public let message: Message

    public init(message: Message, version: Int = ProtocolVersion.current,
                id: String = UUID().uuidString, timestampMillis: Int64 = Envelope.nowMillis()) {
        self.version = version
        self.id = id
        self.timestampMillis = timestampMillis
        self.message = message
    }

    public static func nowMillis() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
}

extension String {
    /// The longest prefix whose UTF-8 encoding fits in `maxBytes`, never splitting a character.
    public func truncated(toUTF8Bytes maxBytes: Int) -> String {
        guard utf8.count > maxBytes else { return self }
        var result = ""
        for character in self {
            guard result.utf8.count + String(character).utf8.count <= maxBytes else { break }
            result.append(character)
        }
        return result
    }
}
