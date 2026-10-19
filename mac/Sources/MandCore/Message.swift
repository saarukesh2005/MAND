import Foundation

/// The `hello` body (protocol §3).
public struct Hello: Equatable, Sendable {
    public enum Platform: String, Sendable { case mac, android }

    public let name: String
    public let platform: Platform
    public let versions: ClosedRange<Int>
    public let app: String

    public init(name: String, platform: Platform, versions: ClosedRange<Int>, app: String) {
        self.name = name
        self.platform = platform
        self.versions = versions
        self.app = app
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
    case unknown(type: String)

    public static let maxTextBytes = 16_384
    public static let maxNameLength = 64

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
        case .unknown(let type): type
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
