package dev.mand.core

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * Strict JSON encoding/decoding of envelopes (protocol §3).
 * Decoding treats input as untrusted: any rule violation throws [ProtocolError.MALFORMED].
 */
object EnvelopeCodec {
    private const val MAX_ID_BYTES = 64
    private const val MAX_TYPE_BYTES = 64
    private val TYPE_PATTERN = Regex("^[a-z0-9._]+$")

    fun encode(envelope: Envelope): ByteArray {
        val json = buildJsonObject {
            put("v", envelope.version)
            put("type", envelope.message.type)
            put("id", envelope.id)
            put("ts", envelope.timestampMillis)
            put("body", body(envelope.message))
        }
        return json.toString().toByteArray(Charsets.UTF_8)
    }

    fun decode(data: ByteArray): Envelope {
        val root = try {
            Json.parseToJsonElement(data.toString(Charsets.UTF_8)) as? JsonObject
        } catch (e: Exception) {
            null
        } ?: malformed()

        val version = integer(root["v"])?.takeIf { it >= 1 } ?: malformed()
        val type = string(root["type"], MAX_TYPE_BYTES)?.takeIf { TYPE_PATTERN.matches(it) } ?: malformed()
        val id = string(root["id"], MAX_ID_BYTES) ?: malformed()
        val timestamp = integer(root["ts"]) ?: malformed()
        val body = root["body"] as? JsonObject ?: malformed()
        if (version > Int.MAX_VALUE) malformed()
        return Envelope(parseMessage(type, body), version.toInt(), id, timestamp)
    }

    private fun parseMessage(type: String, body: JsonObject): Message = when (type) {
        "hello" -> Message.HelloMessage(parseHello(body))
        "pair.request" -> Message.PairRequest(required(body["proof"], 128))
        "pair.result" -> Message.PairResult(
            accepted = boolean(body["accepted"]) ?: malformed(),
            reason = optional(body["reason"], 64),
        )
        "session.ready" -> Message.SessionReady
        "ping" -> Message.Ping
        "pong" -> Message.Pong(required(body["ref"], MAX_ID_BYTES))
        "text" -> Message.Text(required(body["text"], Message.MAX_TEXT_BYTES))
        "bye" -> Message.Bye(required(body["reason"], 64))
        "error" -> Message.Error(required(body["code"], 64), optional(body["message"], 512))
        else -> Message.Unknown(type)
    }

    private fun parseHello(body: JsonObject): Hello {
        val platform = Hello.Platform.entries.firstOrNull { it.wire == string(body["platform"], 16) } ?: malformed()
        val min = integer(body["minVersion"])?.takeIf { it in 1..Int.MAX_VALUE } ?: malformed()
        val max = integer(body["maxVersion"])?.takeIf { it in min..Int.MAX_VALUE } ?: malformed()
        return Hello(
            name = required(body["name"], Message.MAX_NAME_BYTES),
            platform = platform,
            versions = min.toInt()..max.toInt(),
            app = required(body["app"], 32),
        )
    }

    private fun body(message: Message): JsonObject = buildJsonObject {
        when (message) {
            is Message.HelloMessage -> {
                put("name", message.hello.name)
                put("platform", message.hello.platform.wire)
                put("minVersion", message.hello.versions.first)
                put("maxVersion", message.hello.versions.last)
                put("app", message.hello.app)
            }
            is Message.PairRequest -> put("proof", message.proof)
            is Message.PairResult -> {
                put("accepted", message.accepted)
                message.reason?.let { put("reason", it) }
            }
            is Message.Pong -> put("ref", message.ref)
            is Message.Text -> put("text", message.text)
            is Message.Bye -> put("reason", message.reason)
            is Message.Error -> {
                put("code", message.code)
                message.message?.let { put("message", it) }
            }
            Message.SessionReady, Message.Ping, is Message.Unknown -> Unit
        }
    }

    // --- Strict JSON value helpers ---

    /** Only real JSON integers: rejects strings, booleans, and `1.0`. */
    internal fun integer(element: JsonElement?): Long? {
        val primitive = element as? JsonPrimitive ?: return null
        if (primitive.isString) return null
        val content = primitive.content
        if (content == "true" || content == "false" || content == "null") return null
        if (content.any { it == '.' || it == 'e' || it == 'E' }) return null
        return content.toLongOrNull()
    }

    internal fun boolean(element: JsonElement?): Boolean? {
        val primitive = element as? JsonPrimitive ?: return null
        if (primitive.isString) return null
        return when (primitive.content) {
            "true" -> true
            "false" -> false
            else -> null
        }
    }

    private fun string(element: JsonElement?, maxBytes: Int): String? {
        val primitive = element as? JsonPrimitive ?: return null
        if (!primitive.isString) return null
        val value = primitive.content
        return value.takeIf { it.isNotEmpty() && it.utf8Size() <= maxBytes }
    }

    private fun required(element: JsonElement?, maxBytes: Int): String = string(element, maxBytes) ?: malformed()

    private fun optional(element: JsonElement?, maxBytes: Int): String? =
        if (element == null) null else required(element, maxBytes)

    private fun malformed(): Nothing = throw ProtocolException(ProtocolError.MALFORMED)
}
