package dev.mand.interop

import dev.mand.core.Base64Url
import dev.mand.core.Envelope
import dev.mand.core.EnvelopeCodec
import dev.mand.core.Feature
import dev.mand.core.Fingerprint
import dev.mand.core.FrameDecoder
import dev.mand.core.Framing
import dev.mand.core.Hello
import dev.mand.core.Message
import dev.mand.core.PairingInvitation
import dev.mand.core.PairingProof
import java.io.FileInputStream
import java.net.Socket
import java.security.KeyStore
import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import javax.net.ssl.KeyManagerFactory
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLSocket
import javax.net.ssl.X509TrustManager
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertIs
import kotlin.test.assertTrue
import org.junit.jupiter.api.MethodOrderer
import org.junit.jupiter.api.Order
import org.junit.jupiter.api.TestMethodOrder

/** A minimal JVM mirror of the Android MacSession: same TLS settings, pinning and protocol core. */
private class Client(p12: String, private val pinned: Fingerprint, host: String, port: Int) : AutoCloseable {
    val certificate: X509Certificate
    private val socket: SSLSocket
    private val incoming = LinkedBlockingQueue<Any>()

    init {
        val store = KeyStore.getInstance("PKCS12").apply { FileInputStream(p12).use { load(it, PASSWORD) } }
        certificate = store.getCertificate(store.aliases().nextElement()) as X509Certificate
        val keys = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm()).apply { init(store, PASSWORD) }
        val trust = object : X509TrustManager {
            override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) = throw CertificateException()
            override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) {
                val leaf = chain?.firstOrNull() ?: throw CertificateException("no cert")
                if (Fingerprint.ofCertificate(leaf.encoded) != pinned) throw CertificateException("pin mismatch")
            }
            override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
        }
        val context = SSLContext.getInstance("TLSv1.3").apply { init(keys.keyManagers, arrayOf(trust), null) }
        val plain = Socket(host, port)
        socket = context.socketFactory.createSocket(plain, host, port, true) as SSLSocket
        socket.enabledProtocols = arrayOf("TLSv1.3")
        socket.soTimeout = 10_000
        socket.startHandshake()
        Thread {
            val decoder = FrameDecoder()
            val buffer = ByteArray(65_536)
            try {
                while (true) {
                    val n = socket.inputStream.read(buffer)
                    if (n < 0) break
                    decoder.append(buffer.copyOf(n)).forEach { incoming.put(EnvelopeCodec.decode(it).message) }
                }
            } catch (_: Exception) {
            }
            incoming.put(CLOSED)
        }.apply { isDaemon = true }.start()
    }

    val fingerprint get() = Fingerprint.ofCertificate(certificate.encoded)

    fun send(message: Message) {
        socket.outputStream.write(Framing.encode(EnvelopeCodec.encode(Envelope(message))))
        socket.outputStream.flush()
    }

    /** Next non-ping message, or CLOSED. */
    fun next(): Any {
        while (true) {
            val item = incoming.poll(10, TimeUnit.SECONDS) ?: error("timed out waiting for the Mac")
            if (item is Message.Ping) send(Message.Pong("ping")) else return item
        }
    }

    fun hello() = send(Message.HelloMessage(Hello("Interop Phone", Hello.Platform.ANDROID, 1..1, "interop", Feature.ALL)))

    override fun close() = runCatching { socket.close() }.let { }

    companion object {
        val CLOSED = Any()
        private val PASSWORD = "interop".toCharArray()
    }
}

@TestMethodOrder(MethodOrderer.OrderAnnotation::class)
class InteropTest {
    private val invitation = PairingInvitation.parse(System.getenv("MAND_INVITE"))
    private val phone = System.getenv("MAND_PHONE_P12")
    private val other = System.getenv("MAND_OTHER_P12")
    private fun connect(p12: String, pin: Fingerprint = invitation.fingerprint) =
        Client(p12, pin, invitation.hosts.first(), invitation.port)

    @Test @Order(1)
    fun `wrong pinned fingerprint fails the TLS handshake`() {
        val wrong = Fingerprint.fromHex("00".repeat(32))!!
        assertFailsWith<Exception> { connect(phone, wrong) }
    }

    @Test @Order(2)
    fun `pairs with a Java TLS client, then exchanges text, clipboard and battery`() {
        connect(phone).use { c ->
            val macHello = assertIs<Message.HelloMessage>(c.next())
            assertTrue(Feature.FILES in macHello.hello.features)
            c.hello()
            val proof = PairingProof.compute(invitation.secret, c.fingerprint, invitation.fingerprint)
            c.send(Message.PairRequest(Base64Url.encode(proof)))
            assertEquals(Message.PairResult(true, null), c.next())
            assertEquals(Message.SessionReady, c.next())

            c.send(Message.Text("hello from java"))
            assertEquals(Message.Text("echo:hello from java"), c.next())
            c.send(Message.ClipboardText("clip ✂️"))
            assertEquals(Message.ClipboardText("echo:clip ✂️"), c.next())
            c.send(Message.DeviceStatus(77, true))
            assertEquals(Message.Text("battery:77:true"), c.next())
            c.send(Message.CallStateUpdate(Message.CallState.RINGING, "Amma"))
            assertEquals(Message.CallActionRequest(Message.CallAction.DECLINE), c.next())
        }
    }

    @Test @Order(3)
    fun `paired phone reconnects without pairing again`() {
        connect(phone).use { c ->
            assertIs<Message.HelloMessage>(c.next())
            c.hello()
            assertEquals(Message.SessionReady, c.next())
        }
    }

    @Test @Order(4)
    fun `an unpaired certificate is refused`() {
        val outcome = runCatching {
            connect(other).use { c ->
                c.hello()
                // Either the handshake was refused, or the Mac says not_paired / closes.
                val first = c.next()
                val reply = if (first is Message.HelloMessage) c.next() else first
                reply
            }
        }
        val reply = outcome.getOrNull()
        assertTrue(outcome.isFailure || reply === Client.CLOSED || reply == Message.Error("not_paired", null),
            "unexpected: $reply")
    }
}
