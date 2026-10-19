package dev.mand.android.net

import dev.mand.android.identity.KeystoreIdentity
import dev.mand.core.EnvelopeCodec
import dev.mand.core.Envelope
import dev.mand.core.Fingerprint
import dev.mand.core.FrameDecoder
import dev.mand.core.Framing
import dev.mand.core.Message
import dev.mand.core.ProtocolError
import dev.mand.core.ProtocolException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.IOException
import java.net.InetSocketAddress
import java.net.Socket
import javax.net.ssl.SSLSocket

/**
 * One pinned, mutually-authenticated TLS 1.3 connection to the Mac.
 * Incoming envelopes are delivered through [incoming]; the channel closes when the connection ends.
 */
class MacSession private constructor(private val socket: SSLSocket, val host: String) {
    val incoming = Channel<Envelope>(capacity = 64)
    private val writeLock = Mutex()

    @Volatile var lastReceivedMs: Long = System.currentTimeMillis()
        private set

    /** Why the connection ended, once it has. */
    @Volatile var endReason: String? = null
        private set

    /**
     * Starts the single reader for this session's whole life. Blocking socket reads can't be
     * cancelled cleanly, so phases (pairing, handshake, connected) share this one reader via [incoming].
     */
    fun start(scope: CoroutineScope): Job = scope.launch { endReason = readLoop() }

    private suspend fun readLoop(): String = withContext(Dispatchers.IO) {
        val decoder = FrameDecoder()
        val buffer = ByteArray(64 * 1024)
        val input = socket.inputStream
        try {
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                lastReceivedMs = System.currentTimeMillis()
                for (payload in decoder.append(buffer.copyOf(count))) {
                    incoming.send(EnvelopeCodec.decode(payload))
                }
            }
            "The Mac closed the connection"
        } catch (e: ProtocolException) {
            runCatching { sendNow(Message.Error(e.error.wire, null)) }
            "The Mac sent invalid data (${e.error.wire})"
        } catch (e: IOException) {
            e.message ?: "Connection lost"
        } finally {
            incoming.close()
            close()
        }
    }

    suspend fun send(message: Message) = withContext(Dispatchers.IO) { sendNow(message) }

    private suspend fun sendNow(message: Message) {
        val frame = Framing.encode(EnvelopeCodec.encode(Envelope(message)))
        writeLock.withLock {
            socket.outputStream.write(frame)
            socket.outputStream.flush()
        }
    }

    fun close() {
        runCatching { socket.close() }
    }

    companion object {
        private const val CONNECT_TIMEOUT_MS = 5_000
        private const val HANDSHAKE_TIMEOUT_MS = 10_000

        /**
         * Connects and completes the TLS handshake. Throws if the Mac's certificate isn't [pinnedMac]
         * — so a different computer on the network can never impersonate the paired Mac.
         */
        suspend fun open(host: String, port: Int, pinnedMac: Fingerprint): MacSession = withContext(Dispatchers.IO) {
            val plain = Socket()
            try {
                plain.connect(InetSocketAddress(host, port), CONNECT_TIMEOUT_MS)
                plain.tcpNoDelay = true
                plain.keepAlive = true
                val factory = KeystoreIdentity.sslContext(pinnedMac).socketFactory
                val tls = factory.createSocket(plain, host, port, true) as SSLSocket
                tls.enabledProtocols = arrayOf("TLSv1.3")
                tls.soTimeout = HANDSHAKE_TIMEOUT_MS
                tls.startHandshake()
                tls.soTimeout = 0
                // Defence in depth: re-check the certificate actually used for this session.
                val leaf = tls.session.peerCertificates.firstOrNull()?.encoded
                    ?: throw IOException("The Mac didn’t present a certificate")
                if (Fingerprint.ofCertificate(leaf) != pinnedMac) throw IOException("Certificate mismatch")
                MacSession(tls, host)
            } catch (e: Exception) {
                runCatching { plain.close() }
                throw e
            }
        }
    }
}

/** A protocol-level rejection reported by the Mac (e.g. not paired, pairing declined). */
class MacRejectedException(val error: ProtocolError?, code: String) : Exception(code)
