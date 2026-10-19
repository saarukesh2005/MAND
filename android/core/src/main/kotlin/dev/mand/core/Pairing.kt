package dev.mand.core

import java.security.MessageDigest
import java.util.Base64
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec

/** SHA-256 of a certificate's DER bytes. Identifies a device (protocol §1). */
class Fingerprint private constructor(private val bytes: ByteArray) {
    val hex: String = bytes.joinToString("") { "%02x".format(it) }

    /** Short, human-friendly form, e.g. "B3EA CD33 433B" — matches the Mac's display. */
    val shortDisplay: String get() = hex.take(12).uppercase().chunked(4).joinToString(" ")

    fun toByteArray(): ByteArray = bytes.copyOf()

    override fun equals(other: Any?): Boolean = other is Fingerprint && MessageDigest.isEqual(bytes, other.bytes)
    override fun hashCode(): Int = hex.hashCode()
    override fun toString(): String = shortDisplay

    companion object {
        const val BYTE_COUNT = 32
        private val HEX = Regex("^[0-9a-f]{64}$")

        fun ofCertificate(der: ByteArray): Fingerprint = Fingerprint(MessageDigest.getInstance("SHA-256").digest(der))

        fun fromBytes(bytes: ByteArray): Fingerprint? = if (bytes.size == BYTE_COUNT) Fingerprint(bytes.copyOf()) else null

        fun fromHex(hex: String): Fingerprint? {
            if (!HEX.matches(hex)) return null
            return Fingerprint(ByteArray(BYTE_COUNT) { hex.substring(it * 2, it * 2 + 2).toInt(16).toByte() })
        }
    }
}

/** The pairing proof (protocol §4). */
object PairingProof {
    private val CONTEXT = "MAND-PAIR-v1".toByteArray(Charsets.US_ASCII)
    const val SECRET_BYTES = 32

    fun compute(secret: ByteArray, phone: Fingerprint, mac: Fingerprint): ByteArray {
        val hmac = Mac.getInstance("HmacSHA256")
        hmac.init(SecretKeySpec(secret, "HmacSHA256"))
        hmac.update(CONTEXT)
        hmac.update(phone.toByteArray())
        hmac.update(mac.toByteArray())
        return hmac.doFinal()
    }

    /** Constant-time verification (used by tests; the Mac is the verifier in practice). */
    fun verify(proof: ByteArray, secret: ByteArray, phone: Fingerprint, mac: Fingerprint): Boolean =
        MessageDigest.isEqual(proof, compute(secret, phone, mac))
}

/** Unpadded base64url, as used in the QR code and `pair.request` (padding is rejected). */
object Base64Url {
    fun encode(bytes: ByteArray): String = Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)

    fun decode(text: String): ByteArray? {
        if (text.contains('=')) return null
        return try {
            Base64.getUrlDecoder().decode(text)
        } catch (e: IllegalArgumentException) {
            null
        }
    }
}
