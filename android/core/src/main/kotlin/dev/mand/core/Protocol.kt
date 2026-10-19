package dev.mand.core

/** Error codes from protocol §7. [wire] is the string sent on the network. */
enum class ProtocolError(val wire: String, val userMessage: String) {
    MALFORMED("malformed", "The Mac sent data M’AND couldn’t understand."),
    TOO_LARGE("too_large", "The Mac sent a message that was too large."),
    VERSION_UNSUPPORTED("version_unsupported", "This version of M’AND can’t talk to the Mac. Update both apps."),
    NOT_PAIRED("not_paired", "This phone isn’t paired with the Mac any more. Pair again."),
    PAIRING_EXPIRED("pairing_expired", "The QR code expired. Show a new one on the Mac and scan again."),
    PAIRING_INVALID("pairing_invalid", "Pairing failed a security check. Scan the QR code again."),
    PAIRING_TOO_MANY_ATTEMPTS("pairing_too_many_attempts", "Too many failed attempts. Show a new QR code on the Mac."),
    PAIRING_REJECTED("pairing_rejected", "Pairing was declined on the Mac.");

    companion object {
        fun fromWire(code: String): ProtocolError? = entries.firstOrNull { it.wire == code }
    }
}

class ProtocolException(val error: ProtocolError) : Exception(error.wire)

/** Protocol version support (protocol §5). */
object ProtocolVersion {
    const val CURRENT = 1
    val SUPPORTED = 1..1

    /** The highest version both sides support, or null if they share none. */
    fun negotiate(local: IntRange, remote: IntRange): Int? {
        val chosen = minOf(local.last, remote.last)
        return if (chosen >= maxOf(local.first, remote.first)) chosen else null
    }
}

/** Liveness and reconnection timing (protocol §6). */
object ConnectionTiming {
    const val PING_INTERVAL_MS = 15_000L
    const val DEAD_AFTER_MS = 45_000L
    private val BACKOFF_SECONDS = longArrayOf(1, 2, 4, 8, 16, 30)

    /** Delay before reconnect attempt [attempt] (0-based), capped at 30 s. */
    fun backoffMs(attempt: Int): Long = BACKOFF_SECONDS[attempt.coerceIn(0, BACKOFF_SECONDS.lastIndex)] * 1000

    fun isDead(lastReceivedMs: Long, nowMs: Long): Boolean = nowMs - lastReceivedMs >= DEAD_AFTER_MS
}

/** Length-prefixed framing (protocol §2). */
object Framing {
    const val MAX_PAYLOAD_BYTES = 1_048_576
    internal const val HEADER_BYTES = 4

    fun encode(payload: ByteArray): ByteArray {
        if (payload.isEmpty()) throw ProtocolException(ProtocolError.MALFORMED)
        if (payload.size > MAX_PAYLOAD_BYTES) throw ProtocolException(ProtocolError.TOO_LARGE)
        val n = payload.size
        val header = byteArrayOf((n ushr 24).toByte(), (n ushr 16).toByte(), (n ushr 8).toByte(), n.toByte())
        return header + payload
    }
}

/**
 * Incrementally splits a byte stream into frames. After it throws, close the connection;
 * the decoder is not reusable. Not thread-safe — use from one reader.
 */
class FrameDecoder {
    private var buffer = ByteArray(0)

    val pendingByteCount: Int get() = buffer.size

    fun append(data: ByteArray): List<ByteArray> {
        buffer += data
        val payloads = mutableListOf<ByteArray>()
        var offset = 0
        while (buffer.size - offset >= Framing.HEADER_BYTES) {
            var length = 0L
            for (i in 0 until Framing.HEADER_BYTES) length = (length shl 8) or (buffer[offset + i].toLong() and 0xFF)
            if (length == 0L) throw ProtocolException(ProtocolError.MALFORMED)
            if (length > Framing.MAX_PAYLOAD_BYTES) throw ProtocolException(ProtocolError.TOO_LARGE)
            val start = offset + Framing.HEADER_BYTES
            if (buffer.size - start < length) break
            payloads += buffer.copyOfRange(start, start + length.toInt())
            offset = start + length.toInt()
        }
        buffer = buffer.copyOfRange(offset, buffer.size)
        return payloads
    }
}
