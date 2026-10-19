import CryptoKit
import Foundation

/// SHA-256 of a certificate's DER bytes. Identifies a device (protocol §1).
public struct Fingerprint: Hashable, Sendable, Codable, CustomStringConvertible {
    public static let byteCount = 32
    public let bytes: Data

    public init?(bytes: Data) {
        guard bytes.count == Self.byteCount else { return nil }
        self.bytes = bytes
    }

    public init?(hex: String) {
        guard hex.count == Self.byteCount * 2, let data = Data(hexString: hex) else { return nil }
        self.init(bytes: data)
    }

    public static func of(certificateDER: Data) -> Fingerprint {
        Fingerprint(bytes: Data(SHA256.hash(data: certificateDER)))!
    }

    public var hex: String { bytes.map { String(format: "%02x", $0) }.joined() }

    /// Short, human-friendly form, e.g. "B3EA CD33 433B".
    public var shortDisplay: String {
        stride(from: 0, to: 12, by: 4).map { start in
            let s = hex.index(hex.startIndex, offsetBy: start)
            return hex[s..<hex.index(s, offsetBy: 4)].uppercased()
        }.joined(separator: " ")
    }

    public var description: String { shortDisplay }
}

/// The pairing proof (protocol §4).
public enum PairingProof {
    static let context = Data("MAND-PAIR-v1".utf8)
    public static let secretByteCount = 32

    public static func compute(secret: Data, phone: Fingerprint, mac: Fingerprint) -> Data {
        Data(HMAC<SHA256>.authenticationCode(for: message(phone: phone, mac: mac), using: SymmetricKey(data: secret)))
    }

    /// Constant-time verification.
    public static func verify(_ proof: Data, secret: Data, phone: Fingerprint, mac: Fingerprint) -> Bool {
        HMAC<SHA256>.isValidAuthenticationCode(proof, authenticating: message(phone: phone, mac: mac),
                                               using: SymmetricKey(data: secret))
    }

    private static func message(phone: Fingerprint, mac: Fingerprint) -> Data {
        context + phone.bytes + mac.bytes
    }
}

/// The Mac's open pairing window: a single-use secret with an expiry and an attempt limit.
/// Immutable — every attempt returns the window's next state.
public struct PairingWindow: Sendable, Equatable {
    public static let duration: TimeInterval = 300
    public static let maxAttempts = 3

    public let secret: Data
    public let expiresAt: Date
    public let attemptsRemaining: Int
    public let isConsumed: Bool

    public enum Outcome: Equatable, Sendable {
        case verified
        case rejected(ProtocolError)
    }

    public static func open(now: Date = Date(), secret: Data = randomSecret()) -> PairingWindow {
        PairingWindow(secret: secret, expiresAt: now.addingTimeInterval(duration),
                      attemptsRemaining: maxAttempts, isConsumed: false)
    }

    public static func randomSecret() -> Data {
        SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    }

    public func isUsable(at now: Date) -> Bool {
        !isConsumed && attemptsRemaining > 0 && now < expiresAt
    }

    public func attempt(proof: Data, phone: Fingerprint, mac: Fingerprint, now: Date) -> (Outcome, PairingWindow) {
        if isConsumed || now >= expiresAt { return (.rejected(.pairingExpired), self) }
        if attemptsRemaining <= 0 { return (.rejected(.pairingTooManyAttempts), self) }
        if PairingProof.verify(proof, secret: secret, phone: phone, mac: mac) {
            return (.verified, with(attempts: attemptsRemaining, consumed: true))
        }
        let next = with(attempts: attemptsRemaining - 1, consumed: false)
        return (.rejected(next.attemptsRemaining == 0 ? .pairingTooManyAttempts : .pairingInvalid), next)
    }

    private func with(attempts: Int, consumed: Bool) -> PairingWindow {
        PairingWindow(secret: secret, expiresAt: expiresAt, attemptsRemaining: attempts, isConsumed: consumed)
    }
}

extension Data {
    init?(hexString: String) {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(hexString.count / 2)
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2, limitedBy: hexString.endIndex) ?? hexString.endIndex
            guard let byte = UInt8(hexString[index..<next], radix: 16), hexString.distance(from: index, to: next) == 2
            else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }

    public init?(base64URL: String) {
        var base64 = base64URL.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        guard !base64.contains("=") else { return nil }
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self.init(base64Encoded: base64)
    }

    public var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
