package dev.mand.android.identity

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import dev.mand.core.Fingerprint
import java.math.BigInteger
import java.net.Socket
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.Principal
import java.security.PrivateKey
import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import java.security.spec.ECGenParameterSpec
import java.util.Date
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLEngine
import javax.net.ssl.X509ExtendedKeyManager
import javax.net.ssl.X509ExtendedTrustManager
import javax.security.auth.x500.X500Principal

/**
 * This phone's long-term TLS identity. The P-256 private key is generated inside the Android
 * Keystore and can never be exported. Its certificate fingerprint is what the Mac pins.
 */
object KeystoreIdentity {
    private const val ALIAS = "mand_device_identity"
    private const val PROVIDER = "AndroidKeyStore"
    private const val VALIDITY_MS = 20L * 365 * 24 * 60 * 60 * 1000

    private val keyStore: KeyStore by lazy { KeyStore.getInstance(PROVIDER).apply { load(null) } }

    @Synchronized
    fun certificate(): X509Certificate {
        if (!keyStore.containsAlias(ALIAS)) generate()
        return keyStore.getCertificate(ALIAS) as X509Certificate
    }

    fun fingerprint(): Fingerprint = Fingerprint.ofCertificate(certificate().encoded)

    private fun privateKey(): PrivateKey {
        certificate()
        return keyStore.getKey(ALIAS, null) as PrivateKey
    }

    private fun generate() {
        val now = System.currentTimeMillis()
        // PURPOSE_SIGN without attestation makes the Keystore self-sign the certificate.
        // DIGEST_NONE and SHA256 let the TLS stack sign the handshake with this key.
        val spec = KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_SIGN)
            .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
            .setDigests(KeyProperties.DIGEST_NONE, KeyProperties.DIGEST_SHA256)
            .setCertificateSubject(X500Principal("CN=M'AND Android, O=M'AND"))
            .setCertificateSerialNumber(BigInteger.valueOf(now))
            .setCertificateNotBefore(Date(now - 24 * 60 * 60 * 1000))
            .setCertificateNotAfter(Date(now + VALIDITY_MS))
            .build()
        KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, PROVIDER).apply {
            initialize(spec)
            generateKeyPair()
        }
    }

    /** TLS 1.3 context that presents this identity and accepts only a Mac with [pinnedMac]. */
    fun sslContext(pinnedMac: Fingerprint): SSLContext =
        SSLContext.getInstance("TLSv1.3").apply {
            init(arrayOf(ClientKeyManager()), arrayOf(PinningTrustManager(pinnedMac)), null)
        }

    private class ClientKeyManager : X509ExtendedKeyManager() {
        override fun chooseClientAlias(keyType: Array<out String>?, issuers: Array<out Principal>?, socket: Socket?) = ALIAS
        override fun chooseEngineClientAlias(keyType: Array<out String>?, issuers: Array<out Principal>?, engine: SSLEngine?) = ALIAS
        override fun getClientAliases(keyType: String?, issuers: Array<out Principal>?) = arrayOf(ALIAS)
        override fun getCertificateChain(alias: String?) = arrayOf(certificate())
        override fun getPrivateKey(alias: String?) = privateKey()
        override fun getServerAliases(keyType: String?, issuers: Array<out Principal>?): Array<String>? = null
        override fun chooseServerAlias(keyType: String?, issuers: Array<out Principal>?, socket: Socket?): String? = null
    }

    /** Trusts exactly one certificate: the one whose SHA-256 fingerprint was paired (or scanned). */
    private class PinningTrustManager(private val pinned: Fingerprint) : X509ExtendedTrustManager() {
        override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) = check(chain)
        override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?, socket: Socket?) = check(chain)
        override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?, engine: SSLEngine?) = check(chain)

        override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) = reject()
        override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?, socket: Socket?) = reject()
        override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?, engine: SSLEngine?) = reject()
        override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()

        private fun check(chain: Array<out X509Certificate>?) {
            val leaf = chain?.firstOrNull() ?: throw CertificateException("No certificate from the Mac")
            if (Fingerprint.ofCertificate(leaf.encoded) != pinned) {
                throw CertificateException("This isn’t your paired Mac (certificate mismatch)")
            }
        }

        private fun reject(): Nothing = throw CertificateException("M’AND never accepts incoming TLS clients")
    }
}
