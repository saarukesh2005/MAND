import Foundation

/// Creates correctly ordered events for this device: per-device sequence numbers and a Lamport
/// clock that always moves past everything already seen (so causality is preserved).
public struct ContextAuthor: Sendable {
    public let origin: String
    public private(set) var seq: Int64
    public private(set) var lamport: Int64

    public init(origin: String, seq: Int64 = 0, lamport: Int64 = 0) {
        self.origin = origin
        self.seq = seq
        self.lamport = lamport
    }

    /// Call with every event stored or received, so new events order after them.
    public mutating func observe(_ events: [ContextEvent]) {
        for e in events {
            lamport = max(lamport, e.lamport)
            if e.origin == origin { seq = max(seq, e.seq) }
        }
    }

    public mutating func make(capsule: String, item: String? = nil, body: ContextEvent.Body,
                              time: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) -> ContextEvent {
        seq += 1
        lamport += 1
        return ContextEvent(id: Self.newID(), origin: origin, seq: seq, lamport: lamport, time: time,
                            capsule: capsule, item: item, body: body)
    }

    public static func newID() -> String { UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "") }
}

/// One difference between two versions of a capsule (Time Machine preview).
public enum CapsuleChange: Equatable, Sendable, Identifiable {
    case field(CapsuleField, from: FieldValue, to: FieldValue)
    case tagAdded(String)
    case tagRemoved(String)
    case itemAdded(CapsuleItem)
    case itemRemoved(CapsuleItem)
    case itemChanged(id: String, title: String, field: ItemField, from: FieldValue, to: FieldValue)

    public var id: String {
        switch self {
        case .field(let f, _, _): "field.\(f.rawValue)"
        case .tagAdded(let t): "tag+.\(t)"
        case .tagRemoved(let t): "tag-.\(t)"
        case .itemAdded(let i): "item+.\(i.id)"
        case .itemRemoved(let i): "item-.\(i.id)"
        case .itemChanged(let id, _, let f, _, _): "item~.\(id).\(f.rawValue)"
        }
    }

    /// Plain-English description for the restore preview.
    public var summary: String {
        switch self {
        case .field(let f, let from, let to): "\(f.rawValue.capitalized): \(Self.text(from)) → \(Self.text(to))"
        case .tagAdded(let t): "Tag added: \(t)"
        case .tagRemoved(let t): "Tag removed: \(t)"
        case .itemAdded(let i): "\(i.kind.rawValue.capitalized) added: \(i.title)"
        case .itemRemoved(let i): "\(i.kind.rawValue.capitalized) removed: \(i.title)"
        case .itemChanged(_, let title, let f, let from, let to):
            "\(title) — \(f.rawValue): \(Self.text(from)) → \(Self.text(to))"
        }
    }

    static func text(_ v: FieldValue) -> String {
        switch v {
        case .string(let s): s.count > 40 ? "“\(s.prefix(40))…”" : "“\(s)”"
        case .int(let i): "\(i)"
        case .bool(let b): b ? "yes" : "no"
        }
    }
}

/// Time Machine: compare any two moments and restore safely by *appending* events.
public enum TimeMachine {
    /// Changes that turn `old` into `new`.
    public static func diff(from old: Capsule, to new: Capsule) -> [CapsuleChange] {
        var changes: [CapsuleChange] = []
        for f in CapsuleField.allCases {
            let a = CapsuleReducer.currentValue(old, f), b = CapsuleReducer.currentValue(new, f)
            if a != b { changes.append(.field(f, from: a, to: b)) }
        }
        changes += new.tags.subtracting(old.tags).sorted().map(CapsuleChange.tagAdded)
        changes += old.tags.subtracting(new.tags).sorted().map(CapsuleChange.tagRemoved)
        let oldItems = Dictionary(uniqueKeysWithValues: old.items.map { ($0.id, $0) })
        let newItems = Dictionary(uniqueKeysWithValues: new.items.map { ($0.id, $0) })
        for item in new.items where oldItems[item.id] == nil { changes.append(.itemAdded(item)) }
        for item in old.items where newItems[item.id] == nil { changes.append(.itemRemoved(item)) }
        for item in new.items {
            guard let before = oldItems[item.id] else { continue }
            for f in ItemField.allCases {
                let a = CapsuleReducer.currentValue(before, f), b = CapsuleReducer.currentValue(item, f)
                if a != b { changes.append(.itemChanged(id: item.id, title: item.title, field: f, from: a, to: b)) }
            }
        }
        return changes
    }

    /// Event bodies that apply `changes` (normally a selection from `diff(from: current, to: past)`).
    /// Each write names the current writer as its base, so a restore never creates a false conflict.
    public static func restore(_ changes: [CapsuleChange], capsule: String,
                               state: ContextState) -> [(item: String?, body: ContextEvent.Body)] {
        changes.map { change in
            switch change {
            case .field(let f, _, let to):
                (nil, .capsuleSet(f, to, base: state.lastWriter[ContextState.key(capsule, nil, f.rawValue)]))
            case .tagAdded(let t): (nil, .tagged(t))
            case .tagRemoved(let t): (nil, .untagged(t))
            case .itemAdded(let i):
                (i.id, .itemAdded(ItemSeed(kind: i.kind, title: i.title, text: i.text, url: i.url,
                                           fileName: i.fileName, sha256: i.sha256, size: i.size)))
            case .itemRemoved(let i): (i.id, .itemRemoved)
            case .itemChanged(let id, _, let f, _, let to):
                (id, .itemSet(f, to, base: state.lastWriter[ContextState.key(capsule, id, f.rawValue)]))
            }
        }
    }

    /// Restoring an added item also needs its later edits (e.g. `done`), which `itemAdded` can't carry.
    public static func followUps(for changes: [CapsuleChange], capsule: String) -> [(item: String?, body: ContextEvent.Body)] {
        changes.compactMap { change in
            guard case .itemAdded(let i) = change, i.done else { return nil }
            return (i.id, .itemSet(.done, .bool(true), base: nil))
        }
    }

    /// Activity timeline: every event, newest first, optionally for one capsule.
    public static func timeline(_ events: [ContextEvent], capsule: String? = nil) -> [ContextEvent] {
        events.filter { capsule == nil || $0.capsule == capsule }
            .sorted { ContextEvent.precedes($1, $0) }
    }
}
