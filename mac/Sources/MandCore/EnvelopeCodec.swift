import Foundation

/// Strict JSON encoding/decoding of envelopes (protocol §3).
/// Decoding treats all input as untrusted: any rule violation throws `.malformed`.
public enum EnvelopeCodec {
    static let maxIdLength = 64
    static let maxTypeLength = 64
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
              let id = object["id"] as? String, !id.isEmpty, id.count <= maxIdLength,
              let timestamp = integer(object["ts"]),
              let body = object["body"] as? [String: Any]
        else { throw .malformed }
        let message = try parseMessage(type: type, body: body)
        return Envelope(message: message, version: version, id: id, timestampMillis: Int64(timestamp))
    }

    static func isValidType(_ type: String) -> Bool {
        !type.isEmpty && type.count <= maxTypeLength && type.allSatisfy(allowedTypeCharacters.contains)
    }

    private static func parseMessage(type: String, body: [String: Any]) throws(ProtocolError) -> Message {
        switch type {
        case "hello": return .hello(try parseHello(body))
        case "pair.request": return .pairRequest(proof: try requiredString(body["proof"], maxLength: 128))
        case "pair.result":
            guard let accepted = boolean(body["accepted"]) else { throw .malformed }
            return .pairResult(accepted: accepted, reason: try optionalString(body["reason"], maxLength: 64))
        case "session.ready": return .sessionReady
        case "ping": return .ping
        case "pong": return .pong(ref: try requiredString(body["ref"], maxLength: maxIdLength))
        case "text":
            guard let text = body["text"] as? String, !text.isEmpty,
                  text.utf8.count <= Message.maxTextBytes else { throw .malformed }
            return .text(text)
        case "bye": return .bye(reason: try requiredString(body["reason"], maxLength: 64))
        case "error":
            return .error(code: try requiredString(body["code"], maxLength: 64),
                          message: try optionalString(body["message"], maxLength: 512))
        default: return .unknown(type: type)
        }
    }

    private static func parseHello(_ body: [String: Any]) throws(ProtocolError) -> Hello {
        guard let platformRaw = body["platform"] as? String,
              let platform = Hello.Platform(rawValue: platformRaw),
              let minVersion = integer(body["minVersion"]), minVersion >= 1,
              let maxVersion = integer(body["maxVersion"]), maxVersion >= minVersion
        else { throw .malformed }
        return Hello(
            name: try requiredString(body["name"], maxLength: Message.maxNameLength),
            platform: platform,
            versions: minVersion...maxVersion,
            app: try requiredString(body["app"], maxLength: 32)
        )
    }

    private static func body(of message: Message) -> [String: Any] {
        switch message {
        case .hello(let hello):
            ["name": hello.name, "platform": hello.platform.rawValue,
             "minVersion": hello.versions.lowerBound, "maxVersion": hello.versions.upperBound, "app": hello.app]
        case .pairRequest(let proof): ["proof": proof]
        case .pairResult(let accepted, let reason):
            reason.map { ["accepted": accepted, "reason": $0] } ?? ["accepted": accepted]
        case .sessionReady, .ping, .unknown: [:]
        case .pong(let ref): ["ref": ref]
        case .text(let text): ["text": text]
        case .bye(let reason): ["reason": reason]
        case .error(let code, let message):
            message.map { ["code": code, "message": $0] } ?? ["code": code]
        }
    }

    // MARK: - Strict JSON value helpers

    /// Accepts only real JSON integers (not booleans, not fractions, not strings).
    static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, !isBoolean(number),
              let exact = Int(exactly: number.doubleValue), Double(exact) == number.doubleValue
        else { return nil }
        return number.intValue
    }

    static func boolean(_ value: Any?) -> Bool? {
        guard let number = value as? NSNumber, isBoolean(number) else { return nil }
        return number.boolValue
    }

    private static func isBoolean(_ number: NSNumber) -> Bool {
        CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    private static func requiredString(_ value: Any?, maxLength: Int) throws(ProtocolError) -> String {
        guard let string = value as? String, !string.isEmpty, string.count <= maxLength else { throw .malformed }
        return string
    }

    private static func optionalString(_ value: Any?, maxLength: Int) throws(ProtocolError) -> String? {
        guard let value else { return nil }
        return try requiredString(value, maxLength: maxLength)
    }
}
