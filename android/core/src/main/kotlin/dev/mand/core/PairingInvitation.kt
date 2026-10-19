package dev.mand.core

import java.io.ByteArrayOutputStream

/** The contents of the Mac's pairing QR code (protocol §4). Parsing treats the text as untrusted. */
data class PairingInvitation(
    val name: String,
    val hosts: List<String>,
    val port: Int,
    val fingerprint: Fingerprint,
    val secret: ByteArray,
    val expiresAtEpochSeconds: Long,
) {
    class ParseException(reason: String) : Exception(reason)

    fun isExpired(nowEpochSeconds: Long = System.currentTimeMillis() / 1000): Boolean =
        nowEpochSeconds >= expiresAtEpochSeconds

    override fun equals(other: Any?): Boolean = other is PairingInvitation && name == other.name &&
        hosts == other.hosts && port == other.port && fingerprint == other.fingerprint &&
        secret.contentEquals(other.secret) && expiresAtEpochSeconds == other.expiresAtEpochSeconds

    override fun hashCode(): Int = fingerprint.hashCode()

    companion object {
        private const val PREFIX = "mand://pair?"
        private const val INVITATION_VERSION = "1"
        private const val MAX_HOSTS = 8
        private val HOST_PATTERN = Regex("^[0-9a-fA-F.:%]{1,64}$")

        fun parse(text: String): PairingInvitation {
            if (!text.startsWith(PREFIX)) throw ParseException("not a M’AND pairing code")
            val query = text.removePrefix(PREFIX).split('&').filter { it.isNotEmpty() }.associate { part ->
                val eq = part.indexOf('=')
                if (eq < 0) percentDecode(part) to "" else percentDecode(part.substring(0, eq)) to percentDecode(part.substring(eq + 1))
            }
            if (query["v"] != INVITATION_VERSION) throw ParseException("unsupported pairing code version")

            val name = query["n"].orEmpty()
            if (name.utf8Size() > Message.MAX_NAME_BYTES) throw ParseException("name too long")

            val hosts = query["h"].orEmpty().split(',').filter { it.isNotEmpty() }
            if (hosts.isEmpty() || hosts.size > MAX_HOSTS || !hosts.all(::isIpLiteral)) {
                throw ParseException("bad host list")
            }
            val port = query["p"]?.toIntOrNull()?.takeIf { it in 1..65_535 } ?: throw ParseException("bad port")
            val fingerprint = query["f"]?.lowercase()?.let { Fingerprint.fromHex(it) } ?: throw ParseException("bad fingerprint")
            val secret = query["s"]?.let { Base64Url.decode(it) }?.takeIf { it.size == PairingProof.SECRET_BYTES }
                ?: throw ParseException("bad secret")
            val expiresAt = query["x"]?.toLongOrNull() ?: throw ParseException("bad expiry")

            return PairingInvitation(name, hosts, port, fingerprint, secret, expiresAt)
        }

        /** Only numeric IPv4 or IPv6 addresses — never DNS names — may appear in a QR code. */
        internal fun isIpLiteral(host: String): Boolean {
            if (!HOST_PATTERN.matches(host)) return false
            if (':' in host) return host.count { it == ':' } >= 2
            val parts = host.split('.')
            return parts.size == 4 && parts.all { part ->
                part.isNotEmpty() && part.length <= 3 && part.all(Char::isDigit) && part.toInt() <= 255
            }
        }

        /** RFC 3986 percent-decoding. Unlike URLDecoder, '+' stays '+' (it is not a space here). */
        private fun percentDecode(text: String): String {
            val out = ByteArrayOutputStream()
            var i = 0
            while (i < text.length) {
                val c = text[i]
                if (c == '%') {
                    if (i + 2 >= text.length) throw ParseException("bad escape")
                    val byte = text.substring(i + 1, i + 3).toIntOrNull(16) ?: throw ParseException("bad escape")
                    out.write(byte)
                    i += 3
                } else {
                    out.write(c.toString().toByteArray(Charsets.UTF_8))
                    i += 1
                }
            }
            return out.toByteArray().toString(Charsets.UTF_8)
        }
    }
}
