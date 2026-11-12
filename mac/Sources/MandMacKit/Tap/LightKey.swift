// Tap to Send: the light key, judged from the MacBook notch's ambient light sensor.
// Thresholds and the room/trigger logic are adapted from TapDrop (github.com/0x1p0/TapDrop,
// Copyright (c) 2026 TapDrop contributors, MIT License — see THIRD_PARTY_NOTICES.md), which measured
// them on a MacBook Air M4 with Android phones. The round judge below is M’AND's own, simplified form.
import Foundation

/// Every light-key number in one place (lux values as the notch sensor reports them).
public enum LightKey {
    // Room (B): a slow follow of the uncovered level. Dark below 5 lux, lit above 8 (first reading: 6).
    static let darkBelow = 5.0
    static let litAbove = 8.0
    static let darkLine = 6.0
    static let followUp = 0.5
    static let followDown = 10.0
    static let darkerThan = 0.7

    // Triggers. DIP (lit room, notch suddenly covered): lux ≤ max(2, 0.30·B) after a peak ≥ 0.75·B and a drop ≥ 3
    // within 1.2 s. RISE (dark room, a screen arriving): lux ≥ max(B + 8, 3·B) and ≥ 8 above the recent minimum.
    static let lookBack = 1.2
    static let roundGap = 1.5
    static let dipFloor = 2.0
    static let dipFraction = 0.30
    static let dipPeak = 0.75
    static let dipMinDrop = 3.0
    static let risePlus = 8.0
    static let riseTimes = 3.0
    static let riseMinStep = 8.0

    // Round timing.
    public static let keyOnWithin = 2.0
    static let seeFrom = 0.040
    static let seeWithin = 0.900
    static let rampWithin = 2.5
    static let rampQuiet = 0.35
    static let rampRise = 2.0
    public static let keyOffWithin = 1.0
    static let fallWithin = 0.45

    // How much light counts. E = what this phone gives pressed on the notch (white − black), learned from its passed
    // taps (median of the last 12, once there are 3), 300 lux until then; clamped to 180…1500.
    static let lightFraction = 0.45
    static let seenFraction = 0.55
    static let riseFraction = 0.4
    static let seenFloor = 40.0
    /// Once bright enough, hold until readings stop climbing (within 4 %) or 0.25 s, so the peak is full brightness.
    static let seenHold = 0.25
    static let plateau = 1.04
    static let blockFraction = 0.75
    static let blockFloor = 12.0
    public static let defaultContact = 300.0
    static let contactMin = 180.0
    static let contactMax = 1500.0
    static let learnKeep = 12
    static let learnMin = 3

    /// Light (white − black) a phone with contact level `e` must show.
    public static func needed(contact e: Double) -> Double {
        lightFraction * min(max(e, contactMin), contactMax)
    }

    static func median(_ values: [Double]) -> Double {
        let v = values.sorted()
        guard !v.isEmpty else { return 0 }
        return v.count % 2 == 1 ? v[v.count / 2] : (v[v.count / 2 - 1] + v[v.count / 2]) / 2
    }
}

public struct LightSample: Equatable, Sendable {
    public let t: TimeInterval
    public let lux: Double
    public init(t: TimeInterval, lux: Double) { self.t = t; self.lux = lux }
}

/// Room baseline, dark flag and DIP / RISE triggers, with no hardware (adapted from TapDrop's NotchDetector).
public struct NotchDetector: Sendable {
    public enum Trigger: String, Sendable { case dip, rise, knock }

    public private(set) var baseline: Double?
    public private(set) var dark: Bool?
    /// B stops following while a round runs.
    public var frozen = false
    private var recent: [LightSample] = []
    private var lastRound: TimeInterval = -.infinity
    private var armedAt: TimeInterval = -.infinity
    private var lastT: TimeInterval?

    public init() {}

    public mutating func rearm(at t: TimeInterval) { armedAt = t }
    public mutating func roundStarted(at t: TimeInterval) { lastRound = t }

    /// Highest reading in [from, to] (the pre-light level P of a round).
    public func peak(from: TimeInterval, to: TimeInterval) -> Double? {
        recent.filter { $0.t >= from && $0.t <= to }.map(\.lux).max()
    }

    /// Feeds one reading; returns a trigger if one fired.
    public mutating func feed(_ s: LightSample, detect: Bool = true) -> Trigger? {
        recent.append(s)
        recent.removeAll { s.t - $0.t > 4 }
        var fired: Trigger?
        if detect, !frozen, let b = baseline, let isDark = dark, s.t - lastRound >= LightKey.roundGap {
            let window = recent.filter { $0.t >= max(s.t - LightKey.lookBack, armedAt) }.map(\.lux)
            if !isDark {
                let peak = window.max() ?? s.lux
                if s.lux <= max(LightKey.dipFloor, LightKey.dipFraction * b), peak >= LightKey.dipPeak * b,
                   peak - s.lux >= LightKey.dipMinDrop { fired = .dip }
            } else {
                let low = window.min() ?? s.lux
                if s.lux >= max(b + LightKey.risePlus, LightKey.riseTimes * b), s.lux - low >= LightKey.riseMinStep {
                    fired = .rise
                }
            }
            if fired != nil { lastRound = s.t }
        }
        if !frozen, fired == nil {
            if let b = baseline {
                let dt = min(1, max(0, s.t - (lastT ?? s.t)))
                let tau = s.lux >= LightKey.darkerThan * b ? LightKey.followUp : LightKey.followDown
                baseline = b + (1 - exp(-dt / tau)) * (s.lux - b)
            } else {
                baseline = s.lux
            }
            let b = baseline ?? s.lux
            switch dark {
            case nil: dark = b < LightKey.darkLine
            case true?: if b > LightKey.litAbove { dark = false }
            case false?: if b < LightKey.darkBelow { dark = true }
            }
        }
        lastT = s.t
        return fired
    }
}

/// Judges one light-key round. The phone shows white (`keyOn`), the notch must see it ("seen"), the phone shows
/// black (`keyOff`), and the notch must fall with it by the phone's own light — and, in a lit room, below the room
/// level, because the black phone sits on the sensor. Anything else fails, and nothing is sent.
public struct LightKeyJudge: Sendable {
    public enum Outcome: Equatable, Sendable {
        case seen
        case passed(light: Double)
        case failed(String)
    }

    public let grabAt: TimeInterval
    public let preLevel: Double
    public let room: Double
    public let dark: Bool
    public let contact: Double
    public private(set) var peak: Double = 0
    private var keyOnAt: TimeInterval?
    private var seenAt: TimeInterval?
    private var keyOffAt: TimeInterval?
    private var lastHighAt: TimeInterval?
    private var reachedAt: TimeInterval?
    private var previous: Double?
    private var lowestAfterOff: Double = .infinity
    public private(set) var done = false

    public init(grabAt: TimeInterval, preLevel: Double, room: Double, dark: Bool, contact: Double = LightKey.defaultContact) {
        self.grabAt = grabAt
        self.preLevel = preLevel
        self.room = room
        self.dark = dark
        self.contact = contact
    }

    var need: Double { LightKey.needed(contact: contact) }

    /// The level the notch must reach after key-on before the phone is told to go black.
    var seenLevel: Double {
        let e = min(max(contact, LightKey.contactMin), LightKey.contactMax)
        return max(LightKey.seenFloor, min(LightKey.seenFraction * e, preLevel + LightKey.riseFraction * e))
    }

    public mutating func keyOn(at t: TimeInterval) -> Outcome? {
        guard !done, keyOnAt == nil else { return nil }
        if t - grabAt > LightKey.keyOnWithin { return finish(.failed("no-light-sent")) }
        keyOnAt = t
        return nil
    }

    public mutating func keyOff(at t: TimeInterval) -> Outcome? {
        guard !done, let seenAt, keyOffAt == nil else { return nil }
        if t - seenAt > LightKey.keyOffWithin { return finish(.failed("no-key-off")) }
        keyOffAt = t
        return nil
    }

    public mutating func sample(_ s: LightSample) -> Outcome? {
        guard !done else { return nil }
        if let keyOffAt {
            guard s.t > keyOffAt else { return nil }
            lowestAfterOff = min(lowestAfterOff, s.lux)
            let fell = peak - s.lux >= need
            let blocked = dark || s.lux <= max(LightKey.blockFraction * room, LightKey.blockFloor)
            if fell && blocked { return finish(.passed(light: peak - s.lux)) }
            return s.t - keyOffAt > LightKey.fallWithin ? finish(.failed(failReason)) : nil
        }
        guard let keyOnAt, s.t >= grabAt + LightKey.seeFrom else { return nil }
        if s.lux > peak + LightKey.rampRise { lastHighAt = s.t }
        peak = max(peak, s.lux)
        defer { previous = s.lux }
        if seenAt == nil {
            if reachedAt == nil, s.lux >= seenLevel { reachedAt = s.t }
            if let reachedAt {
                let steady = previous.map { s.lux <= $0 * LightKey.plateau } ?? false
                if (steady && s.t > reachedAt) || s.t - reachedAt >= LightKey.seenHold {
                    seenAt = s.t
                    return .seen
                }
                return nil
            }
            // Wait while the screen is still brightening, but not forever.
            let ramping = lastHighAt.map { s.t - $0 <= LightKey.rampQuiet } ?? false
            let deadline = ramping ? keyOnAt + LightKey.rampWithin : keyOnAt + LightKey.seeWithin
            if s.t > deadline { return finish(.failed("not-seen")) }
        }
        return nil
    }

    /// Timeouts that need no reading (call periodically).
    public mutating func tick(now: TimeInterval) -> Outcome? {
        guard !done else { return nil }
        if keyOnAt == nil, now - grabAt > LightKey.keyOnWithin { return finish(.failed("no-light-sent")) }
        if let seenAt, keyOffAt == nil, now - seenAt > LightKey.keyOffWithin { return finish(.failed("no-key-off")) }
        if let keyOffAt, now - keyOffAt > LightKey.fallWithin + 0.3 { return finish(.failed(failReason)) }
        if let keyOnAt, seenAt == nil, reachedAt == nil {
            let ramping = lastHighAt.map { now - $0 <= LightKey.rampQuiet } ?? false
            if now - keyOnAt > (ramping ? LightKey.rampWithin : LightKey.seeWithin) { return finish(.failed("not-seen")) }
        }
        return nil
    }

    /// Why the fall didn't count: the phone's light was too weak to have been on the notch, or the notch stayed lit.
    private var failReason: String { peak < need ? "not-seen" : "stayed-lit" }

    private mutating func finish(_ o: Outcome) -> Outcome {
        done = true
        return o
    }
}

/// Learns each phone's contact level E from its passed taps.
public struct ContactLearner: Sendable {
    private var samples: [String: [Double]] = [:]

    public init() {}

    public func contact(for phone: String) -> Double {
        guard let s = samples[phone], s.count >= LightKey.learnMin else { return LightKey.defaultContact }
        return min(max(LightKey.median(s), LightKey.contactMin), LightKey.contactMax)
    }

    public mutating func record(_ light: Double, for phone: String) {
        samples[phone, default: []].append(light)
        if samples[phone]!.count > LightKey.learnKeep { samples[phone]!.removeFirst() }
    }
}
