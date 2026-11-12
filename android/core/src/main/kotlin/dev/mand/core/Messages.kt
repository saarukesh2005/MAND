package dev.mand.core

import java.util.UUID

/** Optional capabilities announced in `hello.features` (protocol §3a). */
object Feature {
    const val FILES = "file.v1"
    const val CLIPBOARD = "clipboard.v1"
    const val DEVICE = "device.v1"
    const val NOTIFICATIONS = "notifications.v1"
    const val CALLS = "calls.v1"
    const val TAP = "tap.v1"
    const val FIND = "find.v1"
    const val LINK = "link.v1"
    const val SCREEN = "screen.v1"
    val ALL = listOf(FILES, CLIPBOARD, DEVICE, NOTIFICATIONS, CALLS, TAP, FIND, LINK, SCREEN)
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
    data class CallStateUpdate(val state: CallState, val caller: String?) : Message("call.state")
    data class CallActionRequest(val action: CallAction) : Message("call.action")
    data object TapKnock : Message("tap.knock")
    data class TapGrab(val round: Long, val dark: Boolean) : Message("tap.grab")
    data class TapDecline(val round: Long, val why: String) : Message("tap.decline")
    data class TapLight(val round: Long, val on: Boolean) : Message("tap.light")
    data class TapSeen(val round: Long) : Message("tap.seen")
    data class TapResult(val round: Long, val ok: Boolean, val why: String?) : Message("tap.result")
    data class DeviceInfo(val model: String, val os: String, val storageFree: Long, val storageTotal: Long) :
        Message("device.info")
    data object FindRing : Message("find.ring")
    data object FindStop : Message("find.stop")
    data class FindState(val ringing: Boolean) : Message("find.state")
    data class LinkOpen(val url: String, val title: String?) : Message("link.open")
    data object ScreenRequest : Message("screen.request")
    data class ScreenStart(val width: Int, val height: Int) : Message("screen.start")
    class ScreenFrame(val seq: Long, val key: Boolean, val data: ByteArray) : Message("screen.frame") {
        override fun equals(other: Any?) =
            other is ScreenFrame && seq == other.seq && key == other.key && data.contentEquals(other.data)
        override fun hashCode() = seq.hashCode() * 31 + key.hashCode()
    }
    data class ScreenStop(val reason: String) : Message("screen.stop")
    data class Unknown(val unknownType: String) : Message(unknownType)

    enum class CallState(val wire: String) { RINGING("ringing"), ACTIVE("active"), IDLE("idle") }
    enum class CallAction(val wire: String) { ANSWER("answer"), DECLINE("decline") }

    companion object {
        const val MAX_TEXT_BYTES = 16_384
        const val MAX_NAME_BYTES = 128
        const val MAX_CLIPBOARD_BYTES = 262_144
        const val MAX_FILE_CHUNK_BYTES = 196_608
        const val MAX_FILE_SIZE = 1L shl 40
        const val MAX_STORAGE_BYTES = 1L shl 50
        /** One encoded video frame (H.264 Annex B) in `screen.frame`; fits a 1 MiB frame after base64. */
        const val MAX_SCREEN_FRAME_BYTES = 600_000
        const val MAX_SCREEN_SIDE = 4_096
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

/** Rules for `link.open` URLs: only web links, so a paired device can never open apps, files or scripts. */
object LinkRules {
    const val MAX_URL_BYTES = 2_048
    const val MAX_TITLE_BYTES = 256

    fun isValid(url: String): Boolean {
        if (url.isEmpty() || url.utf8Size() > MAX_URL_BYTES) return false
        if (url.any { it.code <= 0x20 || it.code == 0x7f }) return false
        val lower = url.lowercase()
        val rest = when {
            lower.startsWith("https://") -> lower.substring(8)
            lower.startsWith("http://") -> lower.substring(7)
            else -> return false
        }
        val host = rest.substringBefore('/')
        return host.isNotEmpty() && !host.startsWith("@")
    }

    /** The first web link in shared text, if the text is essentially just a link (with an optional title). */
    fun extract(text: String?): String? {
        if (text == null) return null
        val candidate = text.trim().split(Regex("\\s+")).lastOrNull { it.startsWith("http://", true) || it.startsWith("https://", true) }
            ?: return null
        return candidate.takeIf(::isValid)
    }
}
