package dev.mand.core

import java.util.UUID

/** The `hello` body (protocol §3). */
data class Hello(val name: String, val platform: Platform, val versions: IntRange, val app: String) {
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
    data class Unknown(val unknownType: String) : Message(unknownType)

    companion object {
        const val MAX_TEXT_BYTES = 16_384
        const val MAX_NAME_BYTES = 128
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
