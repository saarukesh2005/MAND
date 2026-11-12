import Foundation

/// Strict JSON (de)serialisation of context events. Decoding treats input as untrusted (it may come
/// from another device): every rule violation is rejected rather than "fixed".
public enum ContextCodec {
    public enum Failure: Error, Equatable { case invalid(String) }

    static let idCharacters = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
    static let hex = Set("0123456789abcdef")

    // MARK: Encode

    public static func object(_ e: ContextEvent) -> [String: Any] {
        var o: [String: Any] = ["id": e.id, "origin": e.origin, "seq": e.seq, "lamport": e.lamport,
                                "time": e.time, "capsule": e.capsule, "type": e.body.type, "data": data(e.body)]
        if let item = e.item { o["item"] = item }
        return o
    }

    public static func encode(_ events: [ContextEvent]) throws -> Data {
        try JSONSerialization.data(withJSONObject: events.map(object), options: [.sortedKeys])
    }

    static func data(_ body: ContextEvent.Body) -> [String: Any] {
        switch body {
        case .capsuleCreated(let title, let description): ["title": title, "description": description]
        case .capsuleSet(let field, let value, let base): set(field.rawValue, value, base)
        case .tagged(let tag), .untagged(let tag): ["tag": tag]
        case .itemAdded(let s):
            ["kind": s.kind.rawValue, "title": s.title, "text": s.text, "url": s.url,
             "fileName": s.fileName, "sha256": s.sha256, "size": s.size]
        case .itemSet(let field, let value, let base): set(field.rawValue, value, base)
        case .itemRemoved, .capsuleOpened: [:]
        }
    }

    private static func set(_ field: String, _ value: FieldValue, _ base: String?) -> [String: Any] {
        var o: [String: Any] = ["field": field]
        switch value {
        case .string(let s): o["value"] = s
        case .int(let i): o["value"] = i
        case .bool(let b): o["value"] = b
        }
        if let base { o["base"] = base }
        return o
    }

    // MARK: Decode

    public static func decode(_ data: Data) throws(Failure) -> [ContextEvent] {
        guard let list = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else { throw .invalid("not a list") }
        var events: [ContextEvent] = []
        for item in list {
            guard let o = item as? [String: Any] else { throw .invalid("event is not an object") }
            events.append(try event(o))
        }
        return events
    }

    public static func event(_ o: [String: Any]) throws(Failure) -> ContextEvent {
        let id = try identifier(o["id"], "id")
        let origin = try identifier(o["origin"], "origin")
        let capsule = try identifier(o["capsule"], "capsule")
        let item = o["item"] == nil ? nil : try identifier(o["item"], "item")
        let seq = try integer(o["seq"], min: 1, "seq")
        let lamport = try integer(o["lamport"], min: 1, "lamport")
        let time = try integer(o["time"], min: 0, "time")
        guard let type = o["type"] as? String else { throw .invalid("type") }
        guard let d = o["data"] as? [String: Any] else { throw .invalid("data") }

        let body: ContextEvent.Body
        switch type {
        case "capsule.created":
            body = .capsuleCreated(title: try text(d["title"], max: ContextLimits.titleBytes, nonEmpty: true, "title"),
                                   description: try text(d["description"] ?? "", max: ContextLimits.descriptionBytes, "description"))
        case "capsule.set":
            guard let raw = d["field"] as? String, let field = CapsuleField(rawValue: raw) else { throw .invalid("field") }
            body = .capsuleSet(field, try capsuleValue(field, d["value"]), base: try optionalIdentifier(d["base"]))
        case "capsule.tagged", "capsule.untagged":
            let tag = try text(d["tag"], max: ContextLimits.tagBytes, nonEmpty: true, "tag")
            body = type == "capsule.tagged" ? .tagged(tag) : .untagged(tag)
        case "item.added":
            guard item != nil else { throw .invalid("item id") }
            guard let raw = d["kind"] as? String, let kind = ItemKind(rawValue: raw) else { throw .invalid("kind") }
            let sha = try text(d["sha256"] ?? "", max: 64, "sha256")
            guard sha.isEmpty || (sha.count == 64 && sha.allSatisfy(hex.contains)) else { throw .invalid("sha256") }
            body = .itemAdded(ItemSeed(
                kind: kind,
                title: try text(d["title"], max: ContextLimits.titleBytes, nonEmpty: true, "title"),
                text: try text(d["text"] ?? "", max: ContextLimits.textBytes, "text"),
                url: try link(d["url"] ?? ""),
                fileName: try text(d["fileName"] ?? "", max: ContextLimits.fileNameBytes, "fileName"),
                sha256: sha,
                size: try integer(d["size"] ?? 0, min: 0, max: ContextLimits.maxFileSize, "size")))
        case "item.set":
            guard item != nil else { throw .invalid("item id") }
            guard let raw = d["field"] as? String, let field = ItemField(rawValue: raw) else { throw .invalid("field") }
            body = .itemSet(field, try itemValue(field, d["value"]), base: try optionalIdentifier(d["base"]))
        case "item.removed":
            guard item != nil else { throw .invalid("item id") }
            body = .itemRemoved
        case "capsule.opened":
            body = .capsuleOpened
        default:
            throw .invalid("unknown type \(type)")
        }
        return ContextEvent(id: id, origin: origin, seq: seq, lamport: lamport, time: time,
                            capsule: capsule, item: item, body: body)
    }

    static func capsuleValue(_ field: CapsuleField, _ v: Any?) throws(Failure) -> FieldValue {
        switch field {
        case .title: .string(try text(v, max: ContextLimits.titleBytes, nonEmpty: true, "title"))
        case .description: .string(try text(v, max: ContextLimits.descriptionBytes, "description"))
        case .progress: .int(try integer(v, min: 0, max: 100, "progress"))
        case .pinned, .archived, .deleted: .bool(try boolean(v, field.rawValue))
        }
    }

    static func itemValue(_ field: ItemField, _ v: Any?) throws(Failure) -> FieldValue {
        switch field {
        case .title: .string(try text(v, max: ContextLimits.titleBytes, nonEmpty: true, "title"))
        case .text: .string(try text(v, max: ContextLimits.textBytes, "text"))
        case .url: .string(try link(v))
        case .done: .bool(try boolean(v, "done"))
        }
    }

    // MARK: Strict helpers

    static func identifier(_ v: Any?, _ name: String) throws(Failure) -> String {
        guard let s = v as? String, !s.isEmpty, s.utf8.count <= ContextLimits.idBytes,
              s.allSatisfy(idCharacters.contains) else { throw .invalid(name) }
        return s
    }

    static func optionalIdentifier(_ v: Any?) throws(Failure) -> String? {
        guard let v else { return nil }
        return try identifier(v, "base")
    }

    static func text(_ v: Any?, max: Int, nonEmpty: Bool = false, _ name: String) throws(Failure) -> String {
        guard let s = v as? String, s.utf8.count <= max, !(nonEmpty && s.isEmpty) else { throw .invalid(name) }
        return s
    }

    /// Empty, or an absolute link with an allowed scheme.
    static func link(_ v: Any?) throws(Failure) -> String {
        let s = try text(v, max: ContextLimits.urlBytes, "url")
        if s.isEmpty { return s }
        guard let colon = s.firstIndex(of: ":"),
              ContextLimits.urlSchemes.contains(s[..<colon].lowercased()) else { throw .invalid("url scheme") }
        return s
    }

    static func integer(_ v: Any?, min: Int64, max: Int64 = .max, _ name: String) throws(Failure) -> Int64 {
        guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), !CFNumberIsFloatType(n) else {
            throw .invalid(name)
        }
        let value = n.int64Value
        guard value >= min, value <= max else { throw .invalid(name) }
        return value
    }

    static func boolean(_ v: Any?, _ name: String) throws(Failure) -> Bool {
        guard let n = v as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { throw .invalid(name) }
        return n.boolValue
    }
}
