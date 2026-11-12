import Foundation

/// Strict JSON encoding/decoding of envelopes (protocol §3).
/// Decoding treats all input as untrusted: any rule violation throws `.malformed`.
public enum EnvelopeCodec {
    static let maxIdBytes = 64
    static let maxTypeBytes = 64
    static let allowedTypeCharacters = Set("abcdefghijklmnopqrstuvwxyz0123456789._")

    public static func encode(_ envelope: Envelope) throws(ProtocolError) -> Data {
        let object: [String: Any] = [
            "v": envelope.version,
            "type": envelope.message.type,
            "id": envelope.id,
            "ts": envelope.timestampMillis,
            "body": body(of: envelope.message),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            throw .malformed
        }
        return data
    }

    public static func decode(_ data: Data) throws(ProtocolError) -> Envelope {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let version = integer(object["v"]), version >= 1,
              let type = object["type"] as? String, isValidType(type),
              let id = object["id"] as? String, !id.isEmpty, id.utf8.count <= maxIdBytes,
              let timestamp = integer(object["ts"]),
              let body = object["body"] as? [String: Any]
        else { throw .malformed }
        let message = try parseMessage(type: type, body: body)
        return Envelope(message: message, version: version, id: id, timestampMillis: Int64(timestamp))
    }

    static func isValidType(_ type: String) -> Bool {
        !type.isEmpty && type.utf8.count <= maxTypeBytes && type.allSatisfy(allowedTypeCharacters.contains)
    }

    private static func parseMessage(type: String, body: [String: Any]) throws(ProtocolError) -> Message {
        switch type {
        case "hello": return .hello(try parseHello(body))
        case "pair.request": return .pairRequest(proof: try requiredString(body["proof"], maxBytes: 128))
        case "pair.result":
            guard let accepted = boolean(body["accepted"]) else { throw .malformed }
            return .pairResult(accepted: accepted, reason: try optionalString(body["reason"], maxBytes: 64))
        case "session.ready": return .sessionReady
        case "ping": return .ping
        case "pong": return .pong(ref: try requiredString(body["ref"], maxBytes: maxIdBytes))
        case "text":
            guard let text = body["text"] as? String, !text.isEmpty,
                  text.utf8.count <= Message.maxTextBytes else { throw .malformed }
            return .text(text)
        case "bye": return .bye(reason: try requiredString(body["reason"], maxBytes: 64))
        case "error":
            return .error(code: try requiredString(body["code"], maxBytes: 64),
                          message: try optionalString(body["message"], maxBytes: 512))
        case "file.offer":
            let size = try int64(body["size"], in: 0...Message.maxFileSize)
            guard let sha = body["sha256"] as? String, isSHA256Hex(sha) else { throw .malformed }
            return .fileOffer(FileOffer(tid: try tid(body), name: try requiredString(body["name"], maxBytes: 1_024),
                                        size: size, sha256: sha))
        case "file.accept":
            return .fileAccept(tid: try tid(body), offset: try int64(body["offset"], in: 0...Message.maxFileSize))
        case "file.reject":
            return .fileReject(tid: try tid(body), reason: try requiredString(body["reason"], maxBytes: 64))
        case "file.chunk":
            guard let text = body["data"] as? String, let data = Data(base64URL: text),
                  !data.isEmpty, data.count <= Message.maxFileChunkBytes else { throw .malformed }
            return .fileChunk(tid: try tid(body), offset: try int64(body["offset"], in: 0...Message.maxFileSize), data: data)
        case "file.ack":
            return .fileAck(tid: try tid(body), received: try int64(body["received"], in: 0...Message.maxFileSize))
        case "file.done":
            return .fileDone(tid: try tid(body))
        case "file.result":
            guard let ok = boolean(body["ok"]) else { throw .malformed }
            return .fileResult(tid: try tid(body), ok: ok, reason: try optionalString(body["reason"], maxBytes: 64))
        case "file.cancel":
            return .fileCancel(tid: try tid(body), reason: try requiredString(body["reason"], maxBytes: 64))
        case "clipboard.text":
            return .clipboardText(try requiredString(body["text"], maxBytes: Message.maxClipboardBytes))
        case "device.status":
            guard let charging = boolean(body["charging"]) else { throw .malformed }
            return .deviceStatus(battery: Int(try int64(body["battery"], in: 0...100)), charging: charging)
        case "device.info":
            return .deviceInfo(DeviceInfo(
                model: try requiredString(body["model"], maxBytes: Message.maxNameBytes),
                os: try requiredString(body["os"], maxBytes: 64),
                storageFree: try int64(body["storageFree"], in: 0...Message.maxStorageBytes),
                storageTotal: try int64(body["storageTotal"], in: 0...Message.maxStorageBytes)))
        case "find.ring": return .findRing
        case "find.stop": return .findStop
        case "find.state":
            guard let ringing = boolean(body["ringing"]) else { throw .malformed }
            return .findState(ringing: ringing)
        case "link.open":
            let url = try requiredString(body["url"], maxBytes: LinkRules.maxURLBytes)
            guard LinkRules.isValid(url) else { throw .malformed }
            return .linkOpen(url: url, title: try optionalString(body["title"], maxBytes: LinkRules.maxTitleBytes))
        case "notification.posted":
            return .notificationPosted(PhoneNotification(
                key: try requiredString(body["key"], maxBytes: 256),
                app: try requiredString(body["app"], maxBytes: 256),
                appName: try requiredString(body["appName"], maxBytes: 128),
                title: try optionalString(body["title"], maxBytes: 512),
                text: try optionalString(body["text"], maxBytes: 4_096),
                time: try int64(body["time"], in: 0...Int64.max)))
        case "notification.removed":
            return .notificationRemoved(key: try requiredString(body["key"], maxBytes: 256))
        case "notification.dismiss":
            return .notificationDismiss(key: try requiredString(body["key"], maxBytes: 256))
        case "call.state":
            guard let raw = body["state"] as? String, let state = Message.CallState(rawValue: raw) else { throw .malformed }
            return .callState(state, caller: try optionalString(body["caller"], maxBytes: Message.maxNameBytes))
        case "call.action":
            guard let raw = body["action"] as? String, let action = Message.CallAction(rawValue: raw) else { throw .malformed }
            return .callAction(action)
        case "tap.knock": return .tapKnock
        case "tap.grab":
            guard let dark = boolean(body["dark"]) else { throw .malformed }
            return .tapGrab(round: try int64(body["round"], in: 1...Int64(Int32.max)), dark: dark)
        case "tap.decline":
            return .tapDecline(round: try int64(body["round"], in: 1...Int64(Int32.max)),
                               why: try requiredString(body["why"], maxBytes: 64))
        case "tap.light":
            guard let on = boolean(body["on"]) else { throw .malformed }
            return .tapLight(round: try int64(body["round"], in: 1...Int64(Int32.max)), on: on)
        case "tap.seen": return .tapSeen(round: try int64(body["round"], in: 1...Int64(Int32.max)))
        case "tap.result":
            guard let ok = boolean(body["ok"]) else { throw .malformed }
            return .tapResult(round: try int64(body["round"], in: 1...Int64(Int32.max)), ok: ok,
                              why: try optionalString(body["why"], maxBytes: 64))
        default: return .unknown(type: type)
        }
    }

    static let tidCharacters = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
    static let hexCharacters = Set("0123456789abcdef")

    private static func tid(_ body: [String: Any]) throws(ProtocolError) -> String {
        guard let tid = body["tid"] as? String, !tid.isEmpty, tid.utf8.count <= 64,
              tid.allSatisfy(tidCharacters.contains) else { throw .malformed }
        return tid
    }

    static func isSHA256Hex(_ text: String) -> Bool {
        text.utf8.count == 64 && text.allSatisfy(hexCharacters.contains)
    }

    private static func int64(_ value: Any?, in range: ClosedRange<Int64>) throws(ProtocolError) -> Int64 {
        guard let number = integer(value), range.contains(Int64(number)) else { throw .malformed }
        return Int64(number)
    }

    private static func features(_ value: Any?) throws(ProtocolError) -> [String] {
        guard let value else { return [] }
        guard let list = value as? [Any], list.count <= 32 else { throw .malformed }
        var result: [String] = []
        for item in list {
            guard let feature = item as? String, !feature.isEmpty, feature.utf8.count <= 32,
                  feature.allSatisfy(allowedTypeCharacters.contains) else { throw .malformed }
            result.append(feature)
        }
        return result
    }

    private static func parseHello(_ body: [String: Any]) throws(ProtocolError) -> Hello {
        guard let platformRaw = body["platform"] as? String,
              let platform = Hello.Platform(rawValue: platformRaw),
              let minVersion = integer(body["minVersion"]), minVersion >= 1,
              let maxVersion = integer(body["maxVersion"]), maxVersion >= minVersion
        else { throw .malformed }
        return Hello(
            name: try requiredString(body["name"], maxBytes: Message.maxNameBytes),
            platform: platform,
            versions: minVersion...maxVersion,
            app: try requiredString(body["app"], maxBytes: 32),
            features: try features(body["features"])
        )
    }

    private static func body(of message: Message) -> [String: Any] {
        switch message {
        case .hello(let hello):
            ["name": hello.name, "platform": hello.platform.rawValue,
             "minVersion": hello.versions.lowerBound, "maxVersion": hello.versions.upperBound, "app": hello.app,
             "features": hello.features]
        case .pairRequest(let proof): ["proof": proof]
        case .pairResult(let accepted, let reason):
            reason.map { ["accepted": accepted, "reason": $0] } ?? ["accepted": accepted]
        case .sessionReady, .ping, .unknown: [:]
        case .pong(let ref): ["ref": ref]
        case .text(let text): ["text": text]
        case .bye(let reason): ["reason": reason]
        case .error(let code, let message):
            message.map { ["code": code, "message": $0] } ?? ["code": code]
        case .fileOffer(let offer):
            ["tid": offer.tid, "name": offer.name, "size": offer.size, "sha256": offer.sha256]
        case .fileAccept(let tid, let offset): ["tid": tid, "offset": offset]
        case .fileReject(let tid, let reason): ["tid": tid, "reason": reason]
        case .fileChunk(let tid, let offset, let data): ["tid": tid, "offset": offset, "data": data.base64URLEncoded]
        case .fileAck(let tid, let received): ["tid": tid, "received": received]
        case .fileDone(let tid): ["tid": tid]
        case .fileResult(let tid, let ok, let reason):
            reason.map { ["tid": tid, "ok": ok, "reason": $0] } ?? ["tid": tid, "ok": ok]
        case .fileCancel(let tid, let reason): ["tid": tid, "reason": reason]
        case .clipboardText(let text): ["text": text]
        case .deviceStatus(let battery, let charging): ["battery": battery, "charging": charging]
        case .notificationPosted(let n):
            ["key": n.key, "app": n.app, "appName": n.appName, "time": n.time]
                .merging(n.title.map { ["title": $0] } ?? [:]) { a, _ in a }
                .merging(n.text.map { ["text": $0] } ?? [:]) { a, _ in a }
        case .notificationRemoved(let key), .notificationDismiss(let key): ["key": key]
        case .callState(let state, let caller):
            caller.map { ["state": state.rawValue, "caller": $0] } ?? ["state": state.rawValue]
        case .callAction(let action): ["action": action.rawValue]
        case .tapKnock, .findRing, .findStop: [:]
        case .deviceInfo(let info):
            ["model": info.model, "os": info.os, "storageFree": info.storageFree, "storageTotal": info.storageTotal]
        case .findState(let ringing): ["ringing": ringing]
        case .linkOpen(let url, let title): title.map { ["url": url, "title": $0] } ?? ["url": url]
        case .tapGrab(let round, let dark): ["round": round, "dark": dark]
        case .tapDecline(let round, let why): ["round": round, "why": why]
        case .tapLight(let round, let on): ["round": round, "on": on]
        case .tapSeen(let round): ["round": round]
        case .tapResult(let round, let ok, let why):
            why.map { ["round": round, "ok": ok, "why": $0] } ?? ["round": round, "ok": ok]
        }
    }

    // MARK: - Strict JSON value helpers

    /// Accepts only real JSON integers (not booleans, not `1.0`, not strings).
    static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, !isBoolean(number), !CFNumberIsFloatType(number),
              let exact = Int(exactly: number.int64Value) else { return nil }
        return exact
    }

    static func boolean(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, isBoolean(number) else { return nil }
        return number.boolValue
    }

    private static func isBoolean(_ number: NSNumber) -> Bool {
        CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    private static func requiredString(_ value: Any?, maxBytes: Int) throws(ProtocolError) -> String {
        guard let string = value as? String, !string.isEmpty, string.utf8.count <= maxBytes else { throw .malformed }
        return string
    }

    private static func optionalString(_ value: Any?, maxBytes: Int) throws(ProtocolError) -> String? {
        guard let value else { return nil }
        return try requiredString(value, maxBytes: maxBytes)
    }
}
