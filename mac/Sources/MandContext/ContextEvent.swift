import Foundation

/// One immutable entry in the context log (TECHNICAL_DECISIONS D22). All continuity features —
/// Task Capsules, Time Machine, Anywhere sync, Anticipate — are derived by folding these events.
/// Specified in protocol/CONTEXT.md and mirrored by android/core `dev.mand.core.context`.
public struct ContextEvent: Equatable, Hashable, Sendable, Identifiable {
    public let id: String
    /// Device that created the event.
    public let origin: String
    /// Per-origin counter (1, 2, 3…), used for sync version vectors.
    public let seq: Int64
    /// Lamport clock; total order is (lamport, origin, seq, id).
    public let lamport: Int64
    /// Creation time on the origin device, Unix milliseconds.
    public let time: Int64
    public let capsule: String
    public let item: String?
    public let body: Body

    public init(id: String, origin: String, seq: Int64, lamport: Int64, time: Int64,
                capsule: String, item: String? = nil, body: Body) {
        self.id = id
        self.origin = origin
        self.seq = seq
        self.lamport = lamport
        self.time = time
        self.capsule = capsule
        self.item = item
        self.body = body
    }

    public enum Body: Equatable, Hashable, Sendable {
        case capsuleCreated(title: String, description: String)
        case capsuleSet(CapsuleField, FieldValue, base: String?)
        case tagged(String)
        case untagged(String)
        case itemAdded(ItemSeed)
        case itemSet(ItemField, FieldValue, base: String?)
        case itemRemoved
        /// The user opened or resumed the capsule on `origin` (activity signal).
        case capsuleOpened

        public var type: String {
            switch self {
            case .capsuleCreated: "capsule.created"
            case .capsuleSet: "capsule.set"
            case .tagged: "capsule.tagged"
            case .untagged: "capsule.untagged"
            case .itemAdded: "item.added"
            case .itemSet: "item.set"
            case .itemRemoved: "item.removed"
            case .capsuleOpened: "capsule.opened"
            }
        }
    }

    /// Total order used by every device.
    public static func precedes(_ a: ContextEvent, _ b: ContextEvent) -> Bool {
        if a.lamport != b.lamport { return a.lamport < b.lamport }
        if a.origin != b.origin { return a.origin < b.origin }
        if a.seq != b.seq { return a.seq < b.seq }
        return a.id < b.id
    }
}

public enum CapsuleField: String, Sendable, CaseIterable {
    case title, description, progress, pinned, archived, deleted
}

public enum ItemField: String, Sendable, CaseIterable {
    case title, text, url, done
}

public enum FieldValue: Equatable, Hashable, Sendable {
    case string(String)
    case int(Int64)
    case bool(Bool)

    public var string: String? { if case .string(let s) = self { s } else { nil } }
    public var int: Int64? { if case .int(let i) = self { i } else { nil } }
    public var bool: Bool? { if case .bool(let b) = self { b } else { nil } }
}

public enum ItemKind: String, Sendable, CaseIterable, Codable {
    case file, url, note, screenshot, action
}

/// Everything known about an item when it's added.
public struct ItemSeed: Equatable, Hashable, Sendable {
    public var kind: ItemKind
    public var title: String
    public var text: String
    public var url: String
    /// For files and screenshots: content identity, so another device can fetch the same bytes.
    public var fileName: String
    public var sha256: String
    public var size: Int64

    public init(kind: ItemKind, title: String, text: String = "", url: String = "",
                fileName: String = "", sha256: String = "", size: Int64 = 0) {
        self.kind = kind
        self.title = title
        self.text = text
        self.url = url
        self.fileName = fileName
        self.sha256 = sha256
        self.size = size
    }
}

/// Validation limits shared with Kotlin (protocol/CONTEXT.md).
public enum ContextLimits {
    public static let idBytes = 64
    public static let titleBytes = 256
    public static let descriptionBytes = 4_096
    public static let textBytes = 65_536
    public static let urlBytes = 2_048
    public static let tagBytes = 64
    public static let fileNameBytes = 255
    public static let maxFileSize: Int64 = 1 << 40
    /// Only these link schemes can be stored (and later opened) — never javascript:, file:, data: or app schemes.
    public static let urlSchemes: Set<String> = ["http", "https", "mailto", "tel"]
}
