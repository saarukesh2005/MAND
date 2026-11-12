import Foundation
import Testing
@testable import MandCore

@Suite("Framing")
struct FramingTests {
    @Test("A lowered frame limit rejects larger frames as too large")
    func configurableLimit() throws {
        var decoder = FrameDecoder(maxPayloadBytes: 4_096)
        #expect(try decoder.append(Framing.encode(Data(count: 4_096))).count == 1)
        #expect(throws: ProtocolError.tooLarge) { _ = try decoder.append(Framing.encode(Data(count: 4_097))) }
    }

    @Test("Round-trips a payload split across many reads")
    func roundTripAcrossChunks() throws {
        let payload = Data(repeating: 0x41, count: 70_000)
        let frame = try Framing.encode(payload)
        var decoder = FrameDecoder()
        var received: [Data] = []
        for start in stride(from: 0, to: frame.count, by: 1_000) {
            received += try decoder.append(frame.subdata(in: start..<min(start + 1_000, frame.count)))
        }
        #expect(received == [payload])
        #expect(decoder.pendingByteCount == 0)
    }

    @Test("Refuses to encode empty or oversized payloads")
    func encodeLimits() {
        #expect(throws: ProtocolError.malformed) { _ = try Framing.encode(Data()) }
        #expect(throws: ProtocolError.tooLarge) {
            _ = try Framing.encode(Data(count: Framing.maxPayloadBytes + 1))
        }
    }
}

@Suite("Envelope codec")
struct EnvelopeCodecTests {
    static let messages: [Message] = [
        .hello(Hello(name: "MacBook Air", platform: .mac, versions: 1...1, app: "0.1.0")),
        .pairRequest(proof: "abc"),
        .pairResult(accepted: true, reason: nil),
        .pairResult(accepted: false, reason: "pairing_rejected"),
        .sessionReady, .ping, .pong(ref: "x1"), .text("héllo 👋"),
        .bye(reason: "unpaired"), .error(code: "not_paired", message: "nope"),
        .hello(Hello(name: "Pixel", platform: .android, versions: 1...1, app: "0.2.0", features: Feature.all)),
        .fileOffer(FileOffer(tid: "t1", name: "a/b.txt", size: 10, sha256: String(repeating: "a", count: 64))),
        .fileAccept(tid: "t1", offset: 4), .fileReject(tid: "t1", reason: "busy"),
        .fileChunk(tid: "t1", offset: 0, data: Data([1, 2, 3])), .fileAck(tid: "t1", received: 3),
        .fileDone(tid: "t1"), .fileResult(tid: "t1", ok: false, reason: "integrity"), .fileCancel(tid: "t1", reason: "user"),
        .clipboardText("copied"), .deviceStatus(battery: 42, charging: true),
        .notificationPosted(PhoneNotification(key: "k", app: "com.x", appName: "X", title: "T", text: nil, time: 5)),
        .notificationRemoved(key: "k"), .notificationDismiss(key: "k"),
        .callState(.ringing, caller: "Amma"), .callState(.idle, caller: nil), .callAction(.decline),
        .tapKnock, .tapGrab(round: 3, dark: true), .tapDecline(round: 3, why: "paused-app"),
        .tapLight(round: 3, on: false), .tapSeen(round: 3), .tapResult(round: 3, ok: true, why: nil),
        .tapResult(round: 4, ok: false, why: "stayed-lit"),
    ]

    @Test("Every message type round-trips", arguments: messages)
    func roundTrip(message: Message) throws {
        let envelope = Envelope(message: message, id: "id-1", timestampMillis: 42)
        #expect(try EnvelopeCodec.decode(EnvelopeCodec.encode(envelope)) == envelope)
    }

    @Test("Text over 16 KiB is rejected")
    func textLimit() throws {
        let ok = Envelope(message: .text(String(repeating: "a", count: Message.maxTextBytes)))
        _ = try EnvelopeCodec.decode(EnvelopeCodec.encode(ok))
        let tooLong = Envelope(message: .text(String(repeating: "a", count: Message.maxTextBytes + 1)))
        #expect(throws: ProtocolError.malformed) { _ = try EnvelopeCodec.decode(EnvelopeCodec.encode(tooLong)) }
    }

    @Test("Booleans and fractions are not accepted as integers")
    func strictIntegers() {
        #expect(EnvelopeCodec.integer(true) == nil)
        #expect(EnvelopeCodec.integer(1.5) == nil)
        #expect(EnvelopeCodec.integer(7) == 7)
    }
}

@Suite("Pairing window")
struct PairingWindowTests {
    let phone = Fingerprint.of(certificateDER: Data("phone".utf8))
    let mac = Fingerprint.of(certificateDER: Data("mac".utf8))
    let start = Date(timeIntervalSince1970: 1_000)

    @Test("A correct proof is accepted exactly once")
    func singleUse() {
        let window = PairingWindow.open(now: start)
        let proof = PairingProof.compute(secret: window.secret, phone: phone, mac: mac)
        let (first, afterFirst) = window.attempt(proof: proof, phone: phone, mac: mac, now: start)
        #expect(first == .verified)
        let (second, _) = afterFirst.attempt(proof: proof, phone: phone, mac: mac, now: start)
        #expect(second == .rejected(.pairingExpired))
    }

    @Test("An expired window rejects even a correct proof")
    func expiry() {
        let window = PairingWindow.open(now: start)
        let proof = PairingProof.compute(secret: window.secret, phone: phone, mac: mac)
        let later = start.addingTimeInterval(PairingWindow.duration)
        #expect(window.attempt(proof: proof, phone: phone, mac: mac, now: later).0 == .rejected(.pairingExpired))
        #expect(!window.isUsable(at: later))
    }

    @Test("Too many wrong proofs close the window")
    func attemptLimit() {
        var window = PairingWindow.open(now: start)
        let wrong = Data(repeating: 0, count: 32)
        var outcomes: [PairingWindow.Outcome] = []
        for _ in 0..<PairingWindow.maxAttempts {
            let (outcome, next) = window.attempt(proof: wrong, phone: phone, mac: mac, now: start)
            outcomes.append(outcome)
            window = next
        }
        #expect(outcomes.dropLast().allSatisfy { $0 == .rejected(.pairingInvalid) })
        #expect(outcomes.last == .rejected(.pairingTooManyAttempts))
        let correct = PairingProof.compute(secret: window.secret, phone: phone, mac: mac)
        #expect(window.attempt(proof: correct, phone: phone, mac: mac, now: start).0 == .rejected(.pairingTooManyAttempts))
    }

    @Test("A proof made for a different phone certificate is rejected")
    func boundToCertificates() {
        let window = PairingWindow.open(now: start)
        let attacker = Fingerprint.of(certificateDER: Data("attacker".utf8))
        let proof = PairingProof.compute(secret: window.secret, phone: phone, mac: mac)
        #expect(window.attempt(proof: proof, phone: attacker, mac: mac, now: start).0 == .rejected(.pairingInvalid))
    }

    @Test("Secrets are random and 32 bytes")
    func randomSecrets() {
        let a = PairingWindow.randomSecret(), b = PairingWindow.randomSecret()
        #expect(a.count == 32 && b.count == 32 && a != b)
    }
}

@Suite("Timing")
struct TimingTests {
    @Test("Backoff grows then caps at 30 s")
    func backoff() {
        #expect((0..<8).map(ConnectionTiming.backoff) == [1, 2, 4, 8, 16, 30, 30, 30])
        #expect(ConnectionTiming.backoff(attempt: -1) == 1)
    }

    @Test("Connection is dead after 45 s of silence")
    func liveness() {
        #expect(!ConnectionTiming.isDead(lastReceived: 0, now: 44.9))
        #expect(ConnectionTiming.isDead(lastReceived: 0, now: 45))
    }
}

@Suite("Text limits")
struct TextLimitTests {
    @Test("Truncation keeps whole characters within the byte limit")
    func truncation() {
        #expect("héllo".truncated(toUTF8Bytes: 2) == "h")
        #expect("héllo".truncated(toUTF8Bytes: 3) == "hé")
        #expect("👋👋".truncated(toUTF8Bytes: 5) == "👋")
        #expect("abc".truncated(toUTF8Bytes: 10) == "abc")
    }
}
