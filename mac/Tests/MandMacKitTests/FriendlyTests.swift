import Testing
@testable import MandMacKit

@Suite("Friendly wording")
struct FriendlyTests {
    @Test("Latency becomes a word")
    func quality() {
        #expect(Friendly.quality(latencyMs: 8) == .excellent)
        #expect(Friendly.quality(latencyMs: 120) == .good)
        #expect(Friendly.quality(latencyMs: 900) == .slow)
    }

    @Test("Time left needs a real speed and bytes still to go")
    func remaining() {
        #expect(Friendly.secondsRemaining(size: 100, transferred: 50, bytesPerSecond: 10) == 5)
        #expect(Friendly.secondsRemaining(size: 100, transferred: 50, bytesPerSecond: 0) == nil)
        #expect(Friendly.secondsRemaining(size: 100, transferred: 100, bytesPerSecond: 10) == nil)
        #expect(Friendly.secondsRemaining(size: 101, transferred: 0, bytesPerSecond: 10) == 11)
    }

    @Test("Time left reads naturally")
    func timeLeft() {
        #expect(Friendly.timeLeft(4) == "a few seconds left")
        #expect(Friendly.timeLeft(45) == "less than a minute left")
        #expect(Friendly.timeLeft(70) == "about a minute left")
        #expect(Friendly.timeLeft(600) == "about 10 minutes left")
        #expect(Friendly.timeLeft(4000) == "about an hour left")
        #expect(Friendly.timeLeft(4 * 3600) == "about 4 hours left")
    }
}
