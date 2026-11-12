import Foundation

/// A Task Capsule as currently known (derived; never stored as the source of truth).
public struct Capsule: Equatable, Sendable, Identifiable {
    public let id: String
    public var title: String
    public var description: String
    public var tags: Set<String> = []
    public var pinned = false
    public var archived = false
    public var deleted = false
    public var progress: Int64 = 0
    public var createdAt: Int64
    public var createdOn: String
    public var updatedAt: Int64
    /// Last time it was opened/resumed, and on which device.
    public var lastActive: Int64
    public var lastDevice: String
    /// Every device that has touched this capsule, with its last activity time.
    public var devices: [String: Int64] = [:]
    /// Live (non-removed) items in the order they were added.
    public var items: [CapsuleItem] = []

    public var pendingActions: [CapsuleItem] { items.filter { $0.kind == .action && !$0.done } }
    public var completedActions: [CapsuleItem] { items.filter { $0.kind == .action && $0.done } }
}

public struct CapsuleItem: Equatable, Sendable, Identifiable {
    public let id: String
    public var kind: ItemKind
    public var title: String
    public var text: String
    public var url: String
    public var fileName: String
    public var sha256: String
    public var size: Int64
    public var done = false
    public var addedAt: Int64
    public var addedOn: String
}

/// Two devices changed the same field without seeing each other's change. The later one (in the
/// shared order) was kept; the overwritten value is kept here so the user can choose.
public struct ContextConflict: Equatable, Sendable, Identifiable {
    public let capsule: String
    public let item: String?
    public let field: String
    public let kept: FieldValue
    public let keptEvent: String
    public let lost: FieldValue
    public let lostEvent: String
    public var id: String { "\(capsule)/\(item ?? "")/\(field)/\(lostEvent)" }
}

public struct ContextState: Equatable, Sendable {
    public var capsules: [String: Capsule] = [:]
    public var conflicts: [ContextConflict] = []
    /// The last event that wrote each field — what a new local edit should name as its `base`.
    public var lastWriter: [String: String] = [:]

    public static func key(_ capsule: String, _ item: String?, _ field: String) -> String {
        "\(capsule)/\(item ?? "")/\(field)"
    }

    /// Visible capsules: not deleted, pinned first, then most recently active.
    public var visible: [Capsule] {
        capsules.values.filter { !$0.deleted }.sorted {
            if $0.pinned != $1.pinned { return $0.pinned }
            if $0.lastActive != $1.lastActive { return $0.lastActive > $1.lastActive }
            return $0.id < $1.id
        }
    }
}

/// Deterministic fold of the context log (TECHNICAL_DECISIONS D22). Same input → same state on
/// every device, regardless of the order events arrived in. Mirrored in Kotlin; both are checked
/// against protocol/vectors/context-v1.json.
public enum CapsuleReducer {
    /// Folds `events` (any order, duplicates allowed). With `asOf`, only events created at or
    /// before that time count — the Time Machine view of the past.
    public static func fold(_ events: [ContextEvent], asOf: Int64? = nil) -> ContextState {
        var seen = Set<String>()
        let ordered = events.filter { seen.insert($0.id).inserted }.sorted(by: ContextEvent.precedes)
        var state = ContextState()
        for event in ordered {
            if let asOf, event.time > asOf { continue }
            apply(event, to: &state)
        }
        return state
    }

    static func apply(_ e: ContextEvent, to state: inout ContextState) {
        if case .capsuleCreated(let title, let description) = e.body {
            guard state.capsules[e.capsule] == nil else { return }
            state.capsules[e.capsule] = Capsule(
                id: e.capsule, title: title, description: description, createdAt: e.time, createdOn: e.origin,
                updatedAt: e.time, lastActive: e.time, lastDevice: e.origin, devices: [e.origin: e.time])
            state.lastWriter[ContextState.key(e.capsule, nil, "title")] = e.id
            state.lastWriter[ContextState.key(e.capsule, nil, "description")] = e.id
            return
        }
        // Lamport order guarantees creation comes first; anything for an unknown capsule is ignored.
        guard var capsule = state.capsules[e.capsule] else { return }
        capsule.devices[e.origin] = max(capsule.devices[e.origin] ?? 0, e.time)

        switch e.body {
        case .capsuleCreated:
            return
        case .capsuleSet(let field, let value, let base):
            record(e, item: nil, field: field.rawValue, new: value, old: currentValue(capsule, field), base: base, in: &state)
            set(&capsule, field, value)
            capsule.updatedAt = max(capsule.updatedAt, e.time)
        case .tagged(let tag):
            capsule.tags.insert(tag)
            capsule.updatedAt = max(capsule.updatedAt, e.time)
        case .untagged(let tag):
            capsule.tags.remove(tag)
            capsule.updatedAt = max(capsule.updatedAt, e.time)
        case .itemAdded(let seed):
            guard let id = e.item, !capsule.items.contains(where: { $0.id == id }) else { break }
            capsule.items.append(CapsuleItem(id: id, kind: seed.kind, title: seed.title, text: seed.text, url: seed.url,
                                             fileName: seed.fileName, sha256: seed.sha256, size: seed.size,
                                             addedAt: e.time, addedOn: e.origin))
            for f in ["title", "text", "url", "done"] { state.lastWriter[ContextState.key(e.capsule, id, f)] = e.id }
            capsule.updatedAt = max(capsule.updatedAt, e.time)
        case .itemSet(let field, let value, let base):
            guard let id = e.item, let index = capsule.items.firstIndex(where: { $0.id == id }) else { break }
            record(e, item: id, field: field.rawValue, new: value, old: currentValue(capsule.items[index], field),
                   base: base, in: &state)
            set(&capsule.items[index], field, value)
            capsule.updatedAt = max(capsule.updatedAt, e.time)
        case .itemRemoved:
            capsule.items.removeAll { $0.id == e.item }
            capsule.updatedAt = max(capsule.updatedAt, e.time)
        case .capsuleOpened:
            if e.time >= capsule.lastActive {
                capsule.lastActive = e.time
                capsule.lastDevice = e.origin
            }
        }
        state.capsules[e.capsule] = capsule
    }

    /// Detects a concurrent overwrite: the writer named a `base` that isn't the current writer.
    /// A later write that has seen the current value resolves any open conflict on that field.
    static func record(_ e: ContextEvent, item: String?, field: String, new: FieldValue, old: FieldValue,
                       base: String?, in state: inout ContextState) {
        let key = ContextState.key(e.capsule, item, field)
        let current = state.lastWriter[key]
        if let base, let current, base != current, old != new {
            state.conflicts.append(ContextConflict(capsule: e.capsule, item: item, field: field,
                                                   kept: new, keptEvent: e.id, lost: old, lostEvent: current))
        } else if base != nil, base == current {
            state.conflicts.removeAll { $0.capsule == e.capsule && $0.item == item && $0.field == field }
        }
        state.lastWriter[key] = e.id
    }

    static func currentValue(_ c: Capsule, _ f: CapsuleField) -> FieldValue {
        switch f {
        case .title: .string(c.title)
        case .description: .string(c.description)
        case .progress: .int(c.progress)
        case .pinned: .bool(c.pinned)
        case .archived: .bool(c.archived)
        case .deleted: .bool(c.deleted)
        }
    }

    static func currentValue(_ i: CapsuleItem, _ f: ItemField) -> FieldValue {
        switch f {
        case .title: .string(i.title)
        case .text: .string(i.text)
        case .url: .string(i.url)
        case .done: .bool(i.done)
        }
    }

    static func set(_ c: inout Capsule, _ f: CapsuleField, _ v: FieldValue) {
        switch f {
        case .title: if let s = v.string { c.title = s }
        case .description: if let s = v.string { c.description = s }
        case .progress: if let i = v.int { c.progress = i }
        case .pinned: if let b = v.bool { c.pinned = b }
        case .archived: if let b = v.bool { c.archived = b }
        case .deleted: if let b = v.bool { c.deleted = b }
        }
    }

    static func set(_ i: inout CapsuleItem, _ f: ItemField, _ v: FieldValue) {
        switch f {
        case .title: if let s = v.string { i.title = s }
        case .text: if let s = v.string { i.text = s }
        case .url: if let s = v.string { i.url = s }
        case .done: if let b = v.bool { i.done = b }
        }
    }
}

/// Canonical, comparable view used by the shared test vectors (keys and ordering fixed).
public enum ContextSummary {
    public static func of(_ state: ContextState) -> [String: Any] {
        let capsules = state.capsules.values.sorted { $0.id < $1.id }.map { c -> [String: Any] in
            ["id": c.id, "title": c.title, "description": c.description, "tags": c.tags.sorted(),
             "pinned": c.pinned, "archived": c.archived, "deleted": c.deleted, "progress": c.progress,
             "lastDevice": c.lastDevice, "devices": c.devices.keys.sorted(),
             "items": c.items.map { ["id": $0.id, "kind": $0.kind.rawValue, "title": $0.title,
                                     "text": $0.text, "url": $0.url, "done": $0.done] as [String: Any] }]
        }
        let conflicts = state.conflicts.map { c -> [String: Any] in
            ["capsule": c.capsule, "item": c.item ?? "", "field": c.field, "kept": c.keptEvent, "lost": c.lostEvent]
        }
        return ["capsules": capsules, "conflicts": conflicts]
    }
}
