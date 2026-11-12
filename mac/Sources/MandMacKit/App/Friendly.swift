import Foundation

/// Plain-language wording for numbers shown in the UI, so nobody has to read raw milliseconds or bytes.
public enum Friendly {
    public enum Quality: String, Sendable { case excellent = "Excellent", good = "Good", slow = "Slow" }

    /// How a ping round-trip feels to a person.
    public static func quality(latencyMs: Int) -> Quality {
        switch latencyMs {
        case ..<60: .excellent
        case ..<200: .good
        default: .slow
        }
    }

    /// Whole seconds left at the current speed, or nil when there's no reliable speed yet.
    public static func secondsRemaining(size: Int64, transferred: Int64, bytesPerSecond: Double) -> Int? {
        guard bytesPerSecond >= 1, size > transferred else { return nil }
        let seconds = Double(size - transferred) / bytesPerSecond
        guard seconds.isFinite, seconds < 7 * 24 * 3600 else { return nil }
        return Int(seconds.rounded(.up))
    }

    public static func timeLeft(_ seconds: Int) -> String {
        switch seconds {
        case ..<10: "a few seconds left"
        case ..<60: "less than a minute left"
        case ..<90: "about a minute left"
        case ..<3600: "about \(Int((Double(seconds) / 60).rounded())) minutes left"
        case ..<5400: "about an hour left"
        default: "about \(Int((Double(seconds) / 3600).rounded())) hours left"
        }
    }

    public static func storage(free: Int64, total: Int64) -> String {
        let format = { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
        return total > 0 ? "\(format(free)) free of \(format(total))" : "\(format(free)) free"
    }
}
