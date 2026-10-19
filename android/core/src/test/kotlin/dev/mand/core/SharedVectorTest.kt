package dev.mand.core

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import java.io.File
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertIs
import kotlin.test.assertTrue
import kotlin.test.fail

/** Runs protocol/vectors/protocol-v1.json — the same cases the Swift MandCore tests run. */
class SharedVectorTest {
    private val root: JsonObject = Json.parseToJsonElement(
        File(System.getProperty("mand.vectors") ?: error("mand.vectors not set")).readText(),
    ).jsonObject

    private fun cases(section: String) = root[section]!!.jsonArray.map { it.jsonObject }
    private fun JsonObject.str(key: String) = this[key]!!.jsonPrimitive.content
    private fun hex(text: String) = ByteArray(text.length / 2) { text.substring(it * 2, it * 2 + 2).toInt(16).toByte() }

    @Test
    fun framing() {
        for (case in cases("framing")) {
            val name = case.str("name")
            val decoder = FrameDecoder()
            val input = hex(case.str("hex"))
            when (case.str("expect")) {
                "frame" -> assertContentEquals(hex(case.str("payloadHex")), decoder.append(input).single(), name)
                "frames" -> {
                    val expected = case["payloadsHex"]!!.jsonArray.map { hex(it.jsonPrimitive.content) }
                    val actual = decoder.append(input)
                    assertEquals(expected.size, actual.size, name)
                    expected.zip(actual).forEach { (e, a) -> assertContentEquals(e, a, name) }
                }
                "incomplete" -> {
                    assertTrue(decoder.append(input).isEmpty(), name)
                    assertEquals(input.size, decoder.pendingByteCount, name)
                }
                "error" -> {
                    val error = assertFailsWith<ProtocolException>(name) { decoder.append(input) }
                    assertEquals(case.str("code"), error.error.wire, name)
                }
                else -> fail("unknown expectation in $name")
            }
        }
    }

    @Test
    fun envelopes() {
        for (case in cases("envelopes")) {
            val name = case.str("name")
            val data = case.str("json").toByteArray(Charsets.UTF_8)
            if (case.str("expect") == "ok") {
                val envelope = try {
                    EnvelopeCodec.decode(data)
                } catch (e: ProtocolException) {
                    fail("$name: unexpected ${e.error}")
                }
                val type = case.str("type")
                if (type == "unknown") assertIs<Message.Unknown>(envelope.message, name)
                else assertEquals(type, envelope.message.type, name)
            } else {
                val error = assertFailsWith<ProtocolException>(name) { EnvelopeCodec.decode(data) }
                assertEquals(case.str("code"), error.error.wire, name)
            }
        }
    }

    @Test
    fun versionNegotiation() {
        for (case in cases("versionNegotiation")) {
            val local = case["local"]!!.jsonArray.map { it.jsonPrimitive.int }
            val remote = case["remote"]!!.jsonArray.map { it.jsonPrimitive.int }
            val expected = case["expect"].takeIf { it != JsonNull }?.jsonPrimitive?.int
            assertEquals(expected, ProtocolVersion.negotiate(local[0]..local[1], remote[0]..remote[1]), case.toString())
        }
    }

    @Test
    fun pairingProof() {
        for (case in cases("pairingProof")) {
            val secret = Base64Url.decode(case.str("secretB64"))!!
            val phone = Fingerprint.fromHex(case.str("phoneFpHex"))!!
            val mac = Fingerprint.fromHex(case.str("macFpHex"))!!
            val proof = Base64Url.decode(case.str("proofB64"))!!
            val valid = case["valid"]!!.jsonPrimitive.content.toBoolean()
            assertEquals(valid, PairingProof.verify(proof, secret, phone, mac), case.str("name"))
            if (valid) assertContentEquals(proof, PairingProof.compute(secret, phone, mac))
        }
    }

    @Test
    fun invitations() {
        for (case in cases("invitations")) {
            val name = case.str("name")
            val url = case.str("url")
            if (case.str("expect") != "ok") {
                assertFailsWith<PairingInvitation.ParseException>(name) { PairingInvitation.parse(url) }
                continue
            }
            val fields = case["fields"]!!.jsonObject
            val invitation = PairingInvitation.parse(url)
            assertEquals(fields.str("name"), invitation.name, name)
            assertEquals((fields["hosts"] as JsonArray).map { it.jsonPrimitive.content }, invitation.hosts, name)
            assertEquals(fields["port"]!!.jsonPrimitive.int, invitation.port, name)
            assertEquals(fields.str("fingerprintHex"), invitation.fingerprint.hex, name)
            assertEquals(fields.str("secretB64"), Base64Url.encode(invitation.secret), name)
            assertEquals(fields["expiresAt"]!!.jsonPrimitive.long, invitation.expiresAtEpochSeconds, name)
        }
    }
}
