import Foundation
import MandCore
@testable import MandMacKit
import Testing

/// Light-key judging with synthetic readings (no hardware). Room ~120 lux unless stated.
@Suite("Tap to Send: light key")
struct LightKeyTests {
    /// Runs a round: readings before key-on, the white phase, key-off, then the black phase.
    func run(room: Double = 120, dark: Bool = false, pre: Double = 1, white: [Double], black: [Double],
             keyOnDelay: Double = 0.1, keyOffDelay: Double = 0.1) -> [LightKeyJudge.Outcome] {
        var judge = LightKeyJudge(grabAt: 0, preLevel: pre, room: room, dark: dark)
        var out: [LightKeyJudge.Outcome] = []
        var t = 0.05
        if let o = judge.keyOn(at: keyOnDelay) { out.append(o) }
        var seenAt: Double?
        for lux in white {
            t += 0.05
            if let o = judge.sample(LightSample(t: t, lux: lux)) {
                out.append(o)
                if o == .seen { seenAt = t; break }
            }
        }
        if let seenAt, let o = judge.keyOff(at: seenAt + keyOffDelay) { out.append(o) }
        t = (seenAt ?? t) + keyOffDelay
        for lux in black {
            t += 0.05
            if let o = judge.sample(LightSample(t: t, lux: lux)) { out.append(o) }
        }
        if let o = judge.tick(now: t + 2) { out.append(o) }
        return out
    }

    @Test("A phone pressed on the notch in a lit room passes")
    func phoneOnNotch() {
        let out = run(white: [60, 250, 340, 345], black: [3])
        #expect(out.first == .seen)
        guard case .passed(let light)? = out.last else { Issue.record("\(out)"); return }
        #expect(light >= 300)
    }

    @Test("A hand covering the notch never makes light")
    func hand() {
        #expect(run(white: [1, 1, 1, 1], black: []).last == .failed("not-seen"))
    }

    @Test("A lamp switched on doesn't go dark on cue")
    func lamp() {
        let out = run(white: [400, 410], black: [410, 405, 400, 400, 400, 400, 400, 400, 400, 400, 400])
        #expect(out.first == .seen)
        #expect(out.last == .failed("stayed-lit"))
    }

    @Test("A phone held a few centimetres away is too weak")
    func phoneFar() {
        let out = run(white: [50, 70, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80, 80], black: [60])
        #expect(out.last == .failed("not-seen"))
    }

    @Test("In a lit room the black phone must block the room light")
    func blocksRoom() {
        // White − black is large, but the reading after black is room level: the phone isn't on the sensor.
        let out = run(room: 300, white: [600, 610], black: [300, 300, 300, 300, 300, 300, 300, 300, 300, 300, 300])
        #expect(out.last == .failed("stayed-lit"))
    }

    @Test("Dark room: the fall alone counts")
    func darkRoom() {
        #expect(run(room: 1, dark: true, pre: 1, white: [200, 330, 332], black: [2]).last == .passed(light: 330))
    }

    @Test("No key-on within 2 s fails")
    func noKeyOn() {
        var judge = LightKeyJudge(grabAt: 0, preLevel: 1, room: 120, dark: false)
        #expect(judge.tick(now: 2.5) == .failed("no-light-sent"))
    }

    @Test("Seen but no key-off within 1 s fails")
    func noKeyOff() {
        var judge = LightKeyJudge(grabAt: 0, preLevel: 1, room: 120, dark: false)
        _ = judge.keyOn(at: 0.1)
        _ = judge.sample(LightSample(t: 0.2, lux: 350))
        #expect(judge.sample(LightSample(t: 0.25, lux: 352)) == .seen)
        #expect(judge.tick(now: 1.5) == .failed("no-key-off"))
    }

    @Test("The room detector fires DIP when the notch is suddenly covered, RISE when light arrives in the dark")
    func triggers() {
        var lit = NotchDetector()
        var fired: [NotchDetector.Trigger] = []
        for i in 0..<40 { if let f = lit.feed(LightSample(t: Double(i) * 0.1, lux: 120)) { fired.append(f) } }
        if let f = lit.feed(LightSample(t: 4.1, lux: 1)) { fired.append(f) }
        #expect(fired == [.dip])

        var dark = NotchDetector()
        fired = []
        for i in 0..<40 { if let f = dark.feed(LightSample(t: Double(i) * 0.1, lux: 1)) { fired.append(f) } }
        if let f = dark.feed(LightSample(t: 4.1, lux: 60)) { fired.append(f) }
        #expect(fired == [.rise])
    }

    @Test("Contact level is learned from passed taps")
    func learning() {
        var learner = ContactLearner()
        #expect(learner.contact(for: "p") == LightKey.defaultContact)
        for v in [400.0, 420, 410] { learner.record(v, for: "p") }
        #expect(learner.contact(for: "p") == 410)
    }
}

/// Fake sensor for coordinator tests.
final class FakeLight: LightSource, @unchecked Sendable {
    var isAvailable = true
    private(set) var running = false
    func start(on queue: DispatchQueue, _ onSample: @escaping @Sendable (LightSample) -> Void) { running = true }
    func stop() { running = false }
}

final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: TimeInterval = 0
    var now: TimeInterval { get { lock.withLock { value } } set { lock.withLock { value = newValue } } }
}

@Suite("Tap to Send: coordinator", .serialized)
struct TapCoordinatorTests {
    let phone = Fingerprint.of(certificateDER: Data("phone".utf8))
    let other = Fingerprint.of(certificateDER: Data("other".utf8))
    let sent = Recorder<(Message, Fingerprint)>()
    let events = Recorder<TapCoordinator.Event>()
    let light = FakeLight()
    let clock = TestClock()

    func make() -> TapCoordinator {
        let tap = TapCoordinator(source: light, clock: { [clock] in clock.now },
                                 send: { [sent] m, p in sent.append((m, p)) }, onEvent: { [events] in events.append($0) })
        tap.setEnabled(true)
        tap.phoneConnected(phone, supportsTap: true)
        return tap
    }

    func room(_ tap: TapCoordinator, lux: Double = 120, until: Double = 4) {
        var t = 0.0
        while t < until { tap.feed(LightSample(t: t, lux: lux)); t += 0.1 }
        clock.now = until
    }

    func grabID() async -> Int64? {
        await sent.wait { if case .tapGrab(let id, _) = $0.0 { id } else { nil } }
    }

    @Test("Cover → grab → white seen → black falls → phone told to send")
    func fullRound() async throws {
        let tap = make()
        room(tap)
        tap.feed(LightSample(t: 4.0, lux: 1))  // the phone covers the notch: DIP
        let id = try #require(await grabID())

        clock.now = 4.1; tap.handle(.tapLight(round: id, on: true), from: phone)
        tap.feed(LightSample(t: 4.2, lux: 350))
        tap.feed(LightSample(t: 4.25, lux: 352))
        #expect(await sent.wait { if case .tapSeen(id) = $0.0 { true } else { nil } } == true)

        clock.now = 4.3; tap.handle(.tapLight(round: id, on: false), from: phone)
        tap.feed(LightSample(t: 4.35, lux: 2))
        let ok = await sent.wait { if case .tapResult(id, let ok, _) = $0.0 { ok } else { nil } }
        #expect(ok == true)
        #expect(await events.wait { if case .passed(let p) = $0 { p } else { nil } } == phone)
        #expect(light.running)
    }

    @Test("A cover with no phone light: the round fails and nothing is sent")
    func handOnly() async throws {
        let tap = make()
        room(tap)
        tap.feed(LightSample(t: 4.0, lux: 1))
        let id = try #require(await grabID())
        clock.now = 4.1; tap.handle(.tapLight(round: id, on: true), from: phone)
        for i in 1...30 { tap.feed(LightSample(t: 4.1 + Double(i) * 0.1, lux: 1)) }
        let result = await sent.wait { if case .tapResult(id, let ok, let why) = $0.0 { (ok, why) } else { nil } }
        #expect(result?.0 == false)
        #expect(result?.1 == "not-seen")
    }

    @Test("Phones without tap support never get grabs, and the sensor only runs with a capable phone")
    func capability() async {
        let tap = TapCoordinator(source: light, send: { [sent] m, p in sent.append((m, p)) }, onEvent: { _ in })
        tap.setEnabled(true)
        tap.phoneConnected(other, supportsTap: false)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(!light.running)
        tap.phoneConnected(phone, supportsTap: true)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(light.running)
        tap.phoneDisconnected(phone)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(!light.running)
    }

    @Test("Turning Tap to Send off stops the sensor")
    func disable() async {
        let tap = make()
        try? await Task.sleep(for: .milliseconds(100))
        #expect(light.running)
        tap.setEnabled(false)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(!light.running)
    }

    @Test("A knock starts a round for that phone only")
    func knock() async throws {
        let tap = make()
        tap.phoneConnected(other, supportsTap: true)
        room(tap)
        tap.handle(.tapKnock, from: phone)
        let target = await sent.wait { if case .tapGrab = $0.0 { $0.1 } else { nil } }
        #expect(target == phone)
        #expect(!sent.all.contains { if case .tapGrab = $0.0 { $0.1 == other } else { false } })
    }

    @Test("A light message for a different round is ignored")
    func staleRound() async throws {
        let tap = make()
        room(tap)
        tap.feed(LightSample(t: 4.0, lux: 1))
        let id = try #require(await grabID())
        tap.handle(.tapLight(round: id + 99, on: true), from: phone)
        tap.feed(LightSample(t: 4.2, lux: 350))
        try? await Task.sleep(for: .milliseconds(200))
        #expect(!sent.all.contains { if case .tapSeen = $0.0 { true } else { false } })
    }
}
