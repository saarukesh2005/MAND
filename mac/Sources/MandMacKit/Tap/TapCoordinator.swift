import Foundation
import MandCore

/// Runs Tap to Send on the Mac: watches the notch sensor while a capable phone is connected, starts a light-key
/// round on a trigger (cover / light / the phone's knock), judges it, and tells the phone whether to send.
/// All state lives on `queue`.
public final class TapCoordinator: @unchecked Sendable {
    public enum Event: Sendable, Equatable {
        case availability(sensor: Bool)
        case roundStarted(trigger: NotchDetector.Trigger)
        case passed(phone: Fingerprint)
        case failed(phone: Fingerprint?, why: String)
        case declined(phone: Fingerprint, why: String)
    }

    public static let roundTimeout: TimeInterval = 5
    static let knockSettle: TimeInterval = 0.25

    public typealias Sender = @Sendable (Message, Fingerprint) -> Void

    let queue = DispatchQueue(label: "dev.mand.mac.tap", qos: .userInteractive)
    private let source: LightSource
    private let send: Sender
    private let onEvent: @Sendable (Event) -> Void
    private let clock: @Sendable () -> TimeInterval

    private var enabled = false
    private var phones: Set<Fingerprint> = []
    private var detector = NotchDetector()
    private var learner = ContactLearner()
    private var nextRound: Int64 = 1
    private var round: Round?
    private var lastSampleTime: TimeInterval = 0

    struct Round {
        let id: Int64
        let targets: Set<Fingerprint>
        var phone: Fingerprint?
        var judge: LightKeyJudge?
        let startedAt: TimeInterval
        let trigger: NotchDetector.Trigger
        let triggerAt: TimeInterval
    }

    public init(source: LightSource = NotchLightSensor(), clock: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
                send: @escaping Sender, onEvent: @escaping @Sendable (Event) -> Void) {
        self.source = source
        self.clock = clock
        self.send = send
        self.onEvent = onEvent
    }

    public var sensorAvailable: Bool { source.isAvailable }

    // MARK: Public API (any thread)

    public func setEnabled(_ on: Bool) {
        queue.async {
            self.enabled = on
            self.onEvent(.availability(sensor: self.source.isAvailable))
            self.updateStreaming()
        }
    }

    public func phoneConnected(_ phone: Fingerprint, supportsTap: Bool) {
        queue.async {
            if supportsTap { self.phones.insert(phone) } else { self.phones.remove(phone) }
            self.updateStreaming()
        }
    }

    public func phoneDisconnected(_ phone: Fingerprint) {
        queue.async {
            self.phones.remove(phone)
            if let round = self.round, round.targets.contains(phone), round.phone == nil || round.phone == phone {
                self.end(failed: "phone-left", phone: phone, tell: false)
            }
            self.updateStreaming()
        }
    }

    /// A tap.* message from a phone.
    public func handle(_ message: Message, from phone: Fingerprint) {
        queue.async { self.receive(message, from: phone) }
    }

    /// For tests: feed a reading as if it came from the sensor.
    func feed(_ sample: LightSample) {
        queue.async { self.process(sample) }
    }

    // MARK: Internals (on queue)

    private func updateStreaming() {
        if enabled && !phones.isEmpty && source.isAvailable {
            source.start(on: queue) { [weak self] sample in self?.process(sample) }
        } else {
            source.stop()
            if let round { end(failed: "stopped", phone: round.phone, tell: true) }
        }
    }

    private func process(_ s: LightSample) {
        lastSampleTime = s.t
        if var r = round {
            if var judge = r.judge {
                let outcome = judge.sample(s) ?? judge.tick(now: s.t)
                r.judge = judge // keep what the judge learned from this reading, verdict or not
                round = r
                if let outcome { resolve(outcome) }
            }
            _ = detector.feed(s, detect: false)
            if let r = round, s.t - r.startedAt > Self.roundTimeout { end(failed: "timeout", phone: r.phone, tell: true) }
            return
        }
        guard enabled, let trigger = detector.feed(s) else { return }
        start(trigger: trigger, targets: phones, at: s.t)
    }

    private func receive(_ message: Message, from phone: Fingerprint) {
        switch message {
        case .tapKnock:
            guard enabled, round == nil, phones.contains(phone) else { return }
            let now = clock()
            queue.asyncAfter(deadline: .now() + Self.knockSettle) {
                guard self.round == nil else { return }
                self.start(trigger: .knock, targets: [phone], at: now)
            }
        case .tapDecline(let id, let why):
            guard var r = round, r.id == id else { return }
            r = Round(id: r.id, targets: r.targets.subtracting([phone]), phone: r.phone, judge: r.judge,
                      startedAt: r.startedAt, trigger: r.trigger, triggerAt: r.triggerAt)
            round = r
            onEvent(.declined(phone: phone, why: why))
            if r.targets.isEmpty { end(failed: "declined", phone: phone, tell: false) }
        case .tapLight(let id, let on):
            guard var r = round, r.id == id, r.targets.contains(phone) else { return }
            if r.phone == nil, on {
                // The first phone to light up owns the round.
                let b = detector.baseline ?? 0
                let pre = detector.peak(from: r.triggerAt - 0.08, to: r.startedAt + 0.04) ?? b
                r.phone = phone
                r.judge = LightKeyJudge(grabAt: r.startedAt, preLevel: pre, room: b, dark: detector.dark ?? true,
                                        contact: learner.contact(for: phone.hex))
                for other in r.targets where other != phone {
                    send(.tapResult(round: id, ok: false, why: "other-phone"), other)
                }
            }
            guard r.phone == phone, var judge = r.judge else { return }
            let now = max(clock(), lastSampleTime)
            let outcome = on ? judge.keyOn(at: now) : judge.keyOff(at: now)
            r.judge = judge
            round = r
            if let outcome { resolve(outcome) }
        default:
            break
        }
    }

    private func start(trigger: NotchDetector.Trigger, targets: Set<Fingerprint>, at t: TimeInterval) {
        guard !targets.isEmpty else { return }
        let id = nextRound
        nextRound += 1
        let now = max(clock(), t)
        detector.frozen = true
        detector.roundStarted(at: now)
        round = Round(id: id, targets: targets, phone: nil, judge: nil, startedAt: now, trigger: trigger, triggerAt: t)
        onEvent(.roundStarted(trigger: trigger))
        let dark = detector.dark ?? true
        for phone in targets { send(.tapGrab(round: id, dark: dark), phone) }
    }

    private func resolve(_ outcome: LightKeyJudge.Outcome) {
        guard let r = round, let phone = r.phone else { return }
        switch outcome {
        case .seen:
            send(.tapSeen(round: r.id), phone)
        case .passed(let light):
            learner.record(light, for: phone.hex)
            send(.tapResult(round: r.id, ok: true, why: nil), phone)
            onEvent(.passed(phone: phone))
            finishRound()
        case .failed(let why):
            end(failed: why, phone: phone, tell: true)
        }
    }

    private func end(failed why: String, phone: Fingerprint?, tell: Bool) {
        guard let r = round else { return }
        if tell {
            for target in (phone.map { [$0] } ?? Array(r.targets)) {
                send(.tapResult(round: r.id, ok: false, why: why), target)
            }
        }
        onEvent(.failed(phone: phone, why: why))
        finishRound()
    }

    private func finishRound() {
        round = nil
        detector.frozen = false
        detector.rearm(at: lastSampleTime + 0.5)
    }
}
