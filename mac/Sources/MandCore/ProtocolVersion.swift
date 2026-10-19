/// Protocol version support (protocol §5).
public enum ProtocolVersion {
    public static let current = 1
    public static let supported: ClosedRange<Int> = 1...1

    /// The highest version both sides support, or `nil` if they share none.
    public static func negotiate(local: ClosedRange<Int>, remote: ClosedRange<Int>) -> Int? {
        let chosen = min(local.upperBound, remote.upperBound)
        return chosen >= max(local.lowerBound, remote.lowerBound) ? chosen : nil
    }
}

/// Liveness and reconnection timing (protocol §6).
public enum ConnectionTiming {
    public static let pingInterval: Double = 15
    public static let deadAfter: Double = 45
    static let backoffSteps: [Double] = [1, 2, 4, 8, 16, 30]

    /// Delay before reconnect attempt number `attempt` (0-based), capped at 30 s.
    public static func backoff(attempt: Int) -> Double {
        backoffSteps[min(max(attempt, 0), backoffSteps.count - 1)]
    }

    public static func isDead(lastReceived: Double, now: Double) -> Bool {
        now - lastReceived >= deadAfter
    }
}
