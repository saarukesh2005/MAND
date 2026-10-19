package dev.mand.core

import java.util.UUID

/** Optional capabilities announced in `hello.features` (protocol §3a). */
object Feature {
    const val FILES = "file.v1"
    const val CLIPBOARD = "clipboard.v1"
    const val DEVICE = "device.v1"
    const val NOTIFICATIONS = "notifications.v1"
    val ALL = listOf(FILES, CLIPBOARD, DEVICE, NOTIFICATIONS)
}

/** The `hello` body (protocol §3). */
data class Hello(
    val name: String,
    val platform: Platform,
    val versions: IntRange,
    val app: String,
    val features: List<String> = emptyList(),
) {
    enum class Platform(val wire: String) { MAC("mac"), ANDROID("android") }
}

/** Every v1 message. Unknown types decode to [Unknown] and must be ignored. */
sealed class Message(val type: String) {
    data class HelloMessage(val hello: Hello) : Message("hello")
    data class PairRequest(val proof: String) : Message("pair.request")
    data class PairResult(val accepted: Boolean, val reason: String?) : Message("pair.result")
    data object SessionReady : Message("session.ready")
    data object Ping : Message("ping")
    data class Pong(val ref: String) : Message("pong")
    data class Text(val text: String) : Message("text")
    data class Bye(val reason: String) : Message("bye")
    data class Error(val code: String, val message: String?) : Message("error")
    data class FileOffer(val tid: String, val name: String, val size: Long, val sha256: String) : Message("file.offer")
    data class FileAccept(val tid: String, val offset: Long) : Message("file.accept")
    data class FileReject(val tid: String, val reason: String) : Message("file.reject")
    class FileChunk(val tid: String, val offset: Long, val data: ByteArray) : Message("file.chunk") {
        override fun equals(other: Any?) =
            other is FileChunk && tid == other.tid && offset == other.offset && data.contentEquals(other.data)
        override fun hashCode() = tid.hashCode() * 31 + offset.hashCode()
    }
    data class FileAck(val tid: String, val received: Long) : Message("file.ack")
    data class FileDone(val tid: String) : Message("file.done")
    data class FileResult(val tid: String, val ok: Boolean, val reason: String?) : Message("file.result")
    data class FileCancel(val tid: String, val reason: String) : Message("file.cancel")
    data class ClipboardText(val text: String) : Message("clipboard.text")
    data class DeviceStatus(val battery: Int, val charging: Boolean) : Message("device.status")
    data class NotificationPosted(
        val key: String,
        val app: String,
        val appName: String,
        val title: String?,
        val text: String?,
        val time: Long,
    ) : Message("notification.posted")
    data class NotificationRemoved(val key: String) : Message("notification.removed")
    data class NotificationDismiss(val key: String) : Message("notification.dismiss")
    data class Unknown(val unknownType: String) : Message(unknownType)

    companion object {
        const val MAX_TEXT_BYTES = 16_384
        const val MAX_NAME_BYTES = 128
        const val MAX_CLIPBOARD_BYTES = 262_144
        const val MAX_FILE_CHUNK_BYTES = 196_608
        const val MAX_FILE_SIZE = 1L shl 40
    }
}

/** A validated message plus its envelope metadata. */
data class Envelope(
    val message: Message,
    val version: Int = ProtocolVersion.CURRENT,
    val id: String = UUID.randomUUID().toString(),
    val timestampMillis: Long = System.currentTimeMillis(),
)

internal fun String.utf8Size(): Int = toByteArray(Charsets.UTF_8).size

/** The longest prefix whose UTF-8 encoding fits in [maxBytes], never splitting a code point. */
fun String.truncatedToUtf8Bytes(maxBytes: Int): String {
    if (utf8Size() <= maxBytes) return this
    val result = StringBuilder()
    var bytes = 0
    var index = 0
    while (index < length) {
        val codePoint = codePointAt(index)
        val piece = String(Character.toChars(codePoint))
        val size = piece.utf8Size()
        if (bytes + size > maxBytes) break
        result.append(piece)
        bytes += size
        index += Character.charCount(codePoint)
    }
    return result.toString()
}
