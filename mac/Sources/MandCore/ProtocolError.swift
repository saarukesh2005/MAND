/// Error codes defined in protocol §7. Raw values are the wire strings.
public enum ProtocolError: String, Error, Sendable, CaseIterable {
    case malformed
    case tooLarge = "too_large"
    case versionUnsupported = "version_unsupported"
    case notPaired = "not_paired"
    case pairingExpired = "pairing_expired"
    case pairingInvalid = "pairing_invalid"
    case pairingTooManyAttempts = "pairing_too_many_attempts"
    case pairingRejected = "pairing_rejected"

    /// Plain-English explanation suitable for showing to the user.
    public var userMessage: String {
        switch self {
        case .malformed: "The other device sent data M’AND couldn’t understand."
        case .tooLarge: "The other device sent a message that was too large."
        case .versionUnsupported: "This version of M’AND can’t talk to the other device. Update both apps."
        case .notPaired: "This device isn’t paired. Pair it again from the Mac."
        case .pairingExpired: "The pairing code expired. Show a new QR code and scan again."
        case .pairingInvalid: "Pairing failed a security check. Scan the QR code again."
        case .pairingTooManyAttempts: "Too many failed pairing attempts. Show a new QR code."
        case .pairingRejected: "Pairing was declined on the Mac."
        }
    }
}
