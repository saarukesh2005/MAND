package dev.mand.core

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
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
        "file.offer" -> Message.FileOffer(
            tid = tid(body),
            name = required(body["name"], 1_024),
            size = long(body["size"], 0..Message.MAX_FILE_SIZE),
            sha256 = string(body["sha256"], 64)?.takeIf { SHA256_PATTERN.matches(it) } ?: malformed(),
        )
        "file.accept" -> Message.FileAccept(tid(body), long(body["offset"], 0..Message.MAX_FILE_SIZE))
        "file.reject" -> Message.FileReject(tid(body), required(body["reason"], 64))
        "file.chunk" -> {
            val data = string(body["data"], 300_000)?.let { Base64Url.decode(it) }
                ?.takeIf { it.isNotEmpty() && it.size <= Message.MAX_FILE_CHUNK_BYTES } ?: malformed()
            Message.FileChunk(tid(body), long(body["offset"], 0..Message.MAX_FILE_SIZE), data)
        }
        "file.ack" -> Message.FileAck(tid(body), long(body["received"], 0..Message.MAX_FILE_SIZE))
        "file.done" -> Message.FileDone(tid(body))
        "file.result" -> Message.FileResult(tid(body), boolean(body["ok"]) ?: malformed(), optional(body["reason"], 64))
        "file.cancel" -> Message.FileCancel(tid(body), required(body["reason"], 64))
        "clipboard.text" -> Message.ClipboardText(required(body["text"], Message.MAX_CLIPBOARD_BYTES))
        "device.status" -> Message.DeviceStatus(
            battery = long(body["battery"], 0L..100L).toInt(),
            charging = boolean(body["charging"]) ?: malformed(),
        )
        "notification.posted" -> Message.NotificationPosted(
            key = required(body["key"], 256),
            app = required(body["app"], 256),
            appName = required(body["appName"], 128),
            title = optional(body["title"], 512),
            text = optional(body["text"], 4_096),
            time = long(body["time"], 0..Long.MAX_VALUE),
        )
        "notification.removed" -> Message.NotificationRemoved(required(body["key"], 256))
        "notification.dismiss" -> Message.NotificationDismiss(required(body["key"], 256))
        "call.state" -> Message.CallStateUpdate(
            state = Message.CallState.entries.firstOrNull { it.wire == string(body["state"], 16) } ?: malformed(),
            caller = optional(body["caller"], Message.MAX_NAME_BYTES),
        )
        "call.action" -> Message.CallActionRequest(
            Message.CallAction.entries.firstOrNull { it.wire == string(body["action"], 16) } ?: malformed(),
        )
        "tap.knock" -> Message.TapKnock
        "tap.grab" -> Message.TapGrab(long(body["round"], 1L..Int.MAX_VALUE), boolean(body["dark"]) ?: malformed())
        "tap.decline" -> Message.TapDecline(long(body["round"], 1L..Int.MAX_VALUE), required(body["why"], 64))
        "tap.light" -> Message.TapLight(long(body["round"], 1L..Int.MAX_VALUE), boolean(body["on"]) ?: malformed())
        "tap.seen" -> Message.TapSeen(long(body["round"], 1L..Int.MAX_VALUE))
        "tap.result" -> Message.TapResult(
            long(body["round"], 1L..Int.MAX_VALUE), boolean(body["ok"]) ?: malformed(), optional(body["why"], 64),
        )
        else -> Message.Unknown(type)
    }

    private val TID_PATTERN = Regex("^[A-Za-z0-9_-]{1,64}$")
    private val SHA256_PATTERN = Regex("^[0-9a-f]{64}$")
    private val FEATURE_PATTERN = Regex("^[a-z0-9._]{1,32}$")

    private fun tid(body: JsonObject): String =
        string(body["tid"], 64)?.takeIf { TID_PATTERN.matches(it) } ?: malformed()

    private fun long(element: JsonElement?, range: LongRange): Long =
        integer(element)?.takeIf { it in range } ?: malformed()

    private fun features(element: JsonElement?): List<String> {
        if (element == null) return emptyList()
        val array = element as? JsonArray ?: malformed()
        if (array.size > 32) malformed()
        return array.map { item ->
            val primitive = item as? JsonPrimitive ?: malformed()
            if (!primitive.isString || !FEATURE_PATTERN.matches(primitive.content)) malformed()
            primitive.content
        }
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
            features = features(body["features"]),
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
                put("features", JsonArray(message.hello.features.map { JsonPrimitive(it) }))
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
            is Message.FileOffer -> {
                put("tid", message.tid)
                put("name", message.name)
                put("size", message.size)
                put("sha256", message.sha256)
            }
            is Message.FileAccept -> { put("tid", message.tid); put("offset", message.offset) }
            is Message.FileReject -> { put("tid", message.tid); put("reason", message.reason) }
            is Message.FileChunk -> {
                put("tid", message.tid)
                put("offset", message.offset)
                put("data", Base64Url.encode(message.data))
            }
            is Message.FileAck -> { put("tid", message.tid); put("received", message.received) }
            is Message.FileDone -> put("tid", message.tid)
            is Message.FileResult -> {
                put("tid", message.tid)
                put("ok", message.ok)
                message.reason?.let { put("reason", it) }
            }
            is Message.FileCancel -> { put("tid", message.tid); put("reason", message.reason) }
            is Message.ClipboardText -> put("text", message.text)
            is Message.DeviceStatus -> { put("battery", message.battery); put("charging", message.charging) }
            is Message.NotificationPosted -> {
                put("key", message.key)
                put("app", message.app)
                put("appName", message.appName)
                message.title?.let { put("title", it) }
                message.text?.let { put("text", it) }
                put("time", message.time)
            }
            is Message.NotificationRemoved -> put("key", message.key)
            is Message.NotificationDismiss -> put("key", message.key)
            is Message.CallStateUpdate -> {
                put("state", message.state.wire)
                message.caller?.let { put("caller", it) }
            }
            is Message.CallActionRequest -> put("action", message.action.wire)
            is Message.TapGrab -> { put("round", message.round); put("dark", message.dark) }
            is Message.TapDecline -> { put("round", message.round); put("why", message.why) }
            is Message.TapLight -> { put("round", message.round); put("on", message.on) }
            is Message.TapSeen -> put("round", message.round)
            is Message.TapResult -> {
                put("round", message.round)
                put("ok", message.ok)
                message.why?.let { put("why", it) }
            }
            Message.SessionReady, Message.Ping, Message.TapKnock, is Message.Unknown -> Unit
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
