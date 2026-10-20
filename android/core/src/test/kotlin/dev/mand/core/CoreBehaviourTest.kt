package dev.mand.core

import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class CoreBehaviourTest {
    @Test
    fun `payload split across many reads round-trips`() {
        val payload = ByteArray(70_000) { 0x41 }
        val frame = Framing.encode(payload)
        val decoder = FrameDecoder()
        val received = frame.toList().chunked(1_000).flatMap { decoder.append(it.toByteArray()) }
        assertContentEquals(payload, received.single())
        assertEquals(0, decoder.pendingByteCount)
    }

    @Test
    fun `refuses to encode empty or oversized payloads`() {
        assertEquals(ProtocolError.MALFORMED, assertFailsWith<ProtocolException> { Framing.encode(ByteArray(0)) }.error)
        assertEquals(
            ProtocolError.TOO_LARGE,
            assertFailsWith<ProtocolException> { Framing.encode(ByteArray(Framing.MAX_PAYLOAD_BYTES + 1)) }.error,
        )
    }

    @Test
    fun `every message type round-trips`() {
        val messages = listOf(
            Message.HelloMessage(Hello("Pixel 9", Hello.Platform.ANDROID, 1..1, "0.1.0")),
            Message.PairRequest("abc"),
            Message.PairResult(true, null),
            Message.PairResult(false, "pairing_rejected"),
            Message.SessionReady, Message.Ping, Message.Pong("x1"), Message.Text("héllo 👋"),
            Message.Bye("unpaired"), Message.Error("not_paired", "nope"),
            Message.HelloMessage(Hello("Pixel", Hello.Platform.ANDROID, 1..1, "0.2.0", Feature.ALL)),
            Message.FileOffer("t1", "a/b.txt", 10, "a".repeat(64)), Message.FileAccept("t1", 4),
            Message.FileReject("t1", "busy"), Message.FileChunk("t1", 0, byteArrayOf(1, 2, 3)),
            Message.FileAck("t1", 3), Message.FileDone("t1"), Message.FileResult("t1", false, "integrity"),
            Message.FileCancel("t1", "user"), Message.ClipboardText("copied"), Message.DeviceStatus(42, true),
            Message.NotificationPosted("k", "com.x", "X", "T", null, 5),
            Message.NotificationRemoved("k"), Message.NotificationDismiss("k"),
            Message.CallStateUpdate(Message.CallState.RINGING, "Amma"), Message.CallStateUpdate(Message.CallState.IDLE, null),
            Message.CallActionRequest(Message.CallAction.DECLINE),
        )
        for (message in messages) {
            val envelope = Envelope(message, id = "id-1", timestampMillis = 42)
            assertEquals(envelope, EnvelopeCodec.decode(EnvelopeCodec.encode(envelope)), message.type)
        }
    }

    @Test
    fun `strict integers and booleans`() {
        val json = kotlinx.serialization.json.Json
        assertNull(EnvelopeCodec.integer(json.parseToJsonElement("true")))
        assertNull(EnvelopeCodec.integer(json.parseToJsonElement("1.0")))
        assertNull(EnvelopeCodec.integer(json.parseToJsonElement("\"1\"")))
        assertEquals(7L, EnvelopeCodec.integer(json.parseToJsonElement("7")))
        assertNull(EnvelopeCodec.boolean(json.parseToJsonElement("\"true\"")))
    }

    @Test
    fun `proof is bound to both certificates`() {
        val secret = ByteArray(32) { it.toByte() }
        val phone = Fingerprint.ofCertificate("phone".toByteArray())
        val mac = Fingerprint.ofCertificate("mac".toByteArray())
        val attacker = Fingerprint.ofCertificate("attacker".toByteArray())
        val proof = PairingProof.compute(secret, phone, mac)
        assertTrue(PairingProof.verify(proof, secret, phone, mac))
        assertFalse(PairingProof.verify(proof, secret, attacker, mac))
    }

    @Test
    fun `backoff grows then caps at 30 seconds`() {
        assertEquals(listOf(1L, 2, 4, 8, 16, 30, 30, 30).map { it * 1000 }, (0 until 8).map(ConnectionTiming::backoffMs))
        assertEquals(1000L, ConnectionTiming.backoffMs(-1))
    }

    @Test
    fun `connection is dead after 45 seconds of silence`() {
        assertFalse(ConnectionTiming.isDead(0, 44_999))
        assertTrue(ConnectionTiming.isDead(0, 45_000))
    }

    @Test
    fun `truncation keeps whole characters within the byte limit`() {
        assertEquals("h", "héllo".truncatedToUtf8Bytes(2))
        assertEquals("hé", "héllo".truncatedToUtf8Bytes(3))
        assertEquals("👋", "👋👋".truncatedToUtf8Bytes(5))
        assertEquals("abc", "abc".truncatedToUtf8Bytes(10))
    }

    @Test
    fun `fingerprint short display matches the Mac format`() {
        val fp = Fingerprint.fromHex("b3eacd33433b31b5252351032c9b3e7a2e7aa7738d5decdf0dd6c62680853c06")!!
        assertEquals("B3EA CD33 433B", fp.shortDisplay)
        assertNull(Fingerprint.fromHex("B3EA"))
    }
}

class ReconnectPolicyTest {
    @Test
    fun `quick retries first, then a 5 minute resting pace`() {
        assertEquals(1_000L, ReconnectPolicy.delayMs(0))
        assertEquals(30_000L, ReconnectPolicy.delayMs(9))
        assertEquals(300_000L, ReconnectPolicy.delayMs(10))
        assertEquals(300_000L, ReconnectPolicy.delayMs(500))
        assertFalse(ReconnectPolicy.isResting(9))
        assertTrue(ReconnectPolicy.isResting(10))
    }
}
