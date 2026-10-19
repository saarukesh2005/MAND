package dev.mand.android.net

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.provider.Settings
import android.os.Build
import android.util.Log
import dev.mand.android.data.PairedMac
import dev.mand.android.data.PairedMacStore
import dev.mand.android.identity.KeystoreIdentity
import dev.mand.core.Base64Url
import dev.mand.core.ConnectionTiming
import dev.mand.core.Envelope
import dev.mand.core.Hello
import dev.mand.core.Message
import dev.mand.core.PairingInvitation
import dev.mand.core.PairingProof
import dev.mand.core.ProtocolError
import dev.mand.core.ProtocolVersion
import dev.mand.core.truncatedToUtf8Bytes
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.selects.onTimeout
import kotlinx.coroutines.selects.select
import kotlinx.coroutines.withTimeout
import kotlinx.coroutines.withTimeoutOrNull

/**
 * The phone side of M’AND. Owns pairing, the reconnect loop, liveness checks and the test-message chat.
 * Lives for the whole process; the foreground service calls [startLink] / [stopLink].
 */
class BridgeClient private constructor(private val context: Context) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val store = PairedMacStore(context)
    private val discovery = MacDiscovery(context)
    private val kick = Channel<Unit>(Channel.CONFLATED)

    private val _state = MutableStateFlow<LinkState>(LinkState.NotPaired())
    val state: StateFlow<LinkState> = _state.asStateFlow()
    private val _chat = MutableStateFlow<List<ChatLine>>(emptyList())
    val chat: StateFlow<List<ChatLine>> = _chat.asStateFlow()

    @Volatile private var session: MacSession? = null
    /** True while a QR pairing is running; the reconnect loop stays off so the two never race. */
    @Volatile private var isPairing = false
    private var linkJob: Job? = null
    private var pairingJob: Job? = null

    val phoneName: String
        get() = (Settings.Global.getString(context.contentResolver, Settings.Global.DEVICE_NAME) ?: Build.MODEL)
            .truncatedToUtf8Bytes(Message.MAX_NAME_BYTES)

    init {
        scope.launch { refreshIdleState() }
        context.getSystemService(ConnectivityManager::class.java).registerDefaultNetworkCallback(
            object : ConnectivityManager.NetworkCallback() {
                // A network change is the best moment to retry immediately instead of waiting out the backoff.
                override fun onAvailable(network: Network) { kick.trySend(Unit) }
            },
        )
    }

    // ---- Public API ----

    /** Starts (or keeps) the reconnect loop. Called by the foreground service. */
    @Synchronized
    fun startLink() {
        if (isPairing || linkJob?.isActive == true) return
        discovery.start()
        linkJob = scope.launch { runLinkLoop() }
    }

    @Synchronized
    fun stopLink() {
        linkJob?.cancel()
        linkJob = null
        discovery.stop()
        session?.close()
        scope.launch { refreshIdleState(paused = true) }
    }

    /** Pairs using a scanned QR code. Replaces any existing pairing only once the Mac approves. */
    @Synchronized
    fun pair(qrText: String) {
        val invitation = try {
            PairingInvitation.parse(qrText)
        } catch (e: PairingInvitation.ParseException) {
            _state.value = LinkState.NotPaired("That isn’t a M’AND pairing code (${e.message}).")
            return
        }
        if (invitation.isExpired()) {
            _state.value = LinkState.NotPaired("That QR code has expired. Show a new one on the Mac.")
            return
        }
        stopLink()
        pairingJob?.cancel()
        isPairing = true
        pairingJob = scope.launch {
            try {
                runPairing(invitation)
            } finally {
                isPairing = false
            }
            restartLinkIfStillPaired()
        }
    }

    fun sendText(text: String): Boolean {
        val trimmed = text.trim()
        val current = session
        if (trimmed.isEmpty() || trimmed.toByteArray().size > Message.MAX_TEXT_BYTES || current == null) return false
        if (_state.value !is LinkState.Connected) return false
        scope.launch {
            runCatching { current.send(Message.Text(trimmed)) }
                .onSuccess { appendChat(ChatLine(fromMac = false, text = trimmed, atMs = now())) }
                .onFailure { Log.w(TAG, "Test message not sent") }
        }
        return true
    }

    /** Unpairs: tells the Mac (if connected), then deletes the pairing on this phone. */
    fun forgetMac() {
        scope.launch {
            // Give the goodbye a moment to reach the Mac so it forgets this phone too.
            session?.let { current -> withTimeoutOrNull(BYE_TIMEOUT_MS) { runCatching { current.send(Message.Bye("unpaired")) } } }
            stopLink()
            store.clear()
            _chat.value = emptyList()
            _state.value = LinkState.NotPaired("This phone is no longer paired.")
        }
    }

    /** Lets the user point at the Mac manually when discovery fails (reconnect only — never pairs). */
    fun setManualHost(host: String) {
        val trimmed = host.trim()
        if (!trimmed.matches(Regex("^[0-9]{1,3}(\\.[0-9]{1,3}){3}$"))) return
        scope.launch {
            store.current()?.let { store.save(it.copy(lastHost = trimmed)) }
            kick.trySend(Unit)
        }
    }

    // ---- Pairing ----

    private suspend fun runPairing(invitation: PairingInvitation) {
        _state.value = LinkState.Pairing(invitation.name, LinkState.Pairing.Step.CONNECTING)
        var lastError = "Couldn’t reach the Mac. Make sure both are on the same Wi-Fi."
        for (host in invitation.hosts) {
            val opened = try {
                MacSession.open(host, invitation.port, invitation.fingerprint)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.i(TAG, "Pairing connect to a QR address failed: ${e.javaClass.simpleName}")
                lastError = describe(e)
                continue
            }
            opened.start(scope)
            try {
                val paired = pairOver(opened, invitation)
                store.save(paired)
                _chat.value = emptyList()
                runConnected(opened, paired)
                return
            } catch (e: CancellationException) {
                opened.close()
                throw e
            } catch (e: Exception) {
                opened.close()
                _state.value = LinkState.NotPaired(describe(e))
                return
            }
        }
        _state.value = LinkState.NotPaired(lastError)
    }

    /** Runs hello → pair.request → pair.result. Returns the Mac to store once approved. */
    private suspend fun pairOver(session: MacSession, invitation: PairingInvitation): PairedMac {
        val macHello = handshakeHello(session)
        val proof = PairingProof.compute(invitation.secret, KeystoreIdentity.fingerprint(), invitation.fingerprint)
        session.send(Message.PairRequest(Base64Url.encode(proof)))
        _state.value = LinkState.Pairing(macHello.name, LinkState.Pairing.Step.WAITING_FOR_APPROVAL)

        // The Mac answers pair.result, then session.ready once the user clicks Allow.
        val result = withTimeout(APPROVAL_TIMEOUT_MS) { nextMeaningful(session) }
        when (val message = result.message) {
            is Message.PairResult -> if (!message.accepted) {
                throw MacRejectedException(message.reason?.let(ProtocolError::fromWire), message.reason ?: "rejected")
            }
            is Message.Error -> throw MacRejectedException(ProtocolError.fromWire(message.code), message.code)
            else -> throw MacRejectedException(ProtocolError.MALFORMED, "unexpected ${message.type}")
        }
        expectSessionReady(session)
        return PairedMac(invitation.fingerprint, macHello.name, session.host, invitation.port)
    }

    private suspend fun expectSessionReady(session: MacSession) {
        val ready = withTimeout(HANDSHAKE_TIMEOUT_MS) { nextMeaningful(session) }
        when (val message = ready.message) {
            is Message.SessionReady -> Unit
            is Message.Error -> throw MacRejectedException(ProtocolError.fromWire(message.code), message.code)
            else -> throw MacRejectedException(ProtocolError.MALFORMED, "unexpected ${message.type}")
        }
    }

    // ---- Reconnect loop ----

    private suspend fun runLinkLoop() {
        var attempt = 0
        var lastError: String? = null
        while (scope.isActive) {
            val mac = store.current() ?: run {
                refreshIdleState()
                return
            }
            _state.value = LinkState.Searching(mac.name, attempt, lastError)
            val connectedOk = tryConnect(mac) { error -> lastError = error }
            if (store.current() == null) return
            if (connectedOk) {
                attempt = 0
                lastError = null
            } else {
                _state.value = LinkState.Searching(mac.name, attempt, lastError)
                // Wait for the backoff delay, or retry at once when the network changes.
                select<Unit> {
                    kick.onReceive { }
                    onTimeout(ConnectionTiming.backoffMs(attempt)) { }
                }
                attempt += 1
            }
        }
    }

    /** Tries every candidate address once. Returns true if a session was established (and has now ended). */
    private suspend fun tryConnect(mac: PairedMac, onError: (String) -> Unit): Boolean {
        for ((host, port) in candidates(mac)) {
            val opened = try {
                MacSession.open(host, port, mac.fingerprint)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                onError(describe(e))
                continue
            }
            opened.start(scope)
            try {
                handshakeHello(opened)
                expectSessionReady(opened)
                store.save(mac.copy(lastHost = host, port = port))
                onError(runConnected(opened, mac.copy(lastHost = host, port = port)))
                return true
            } catch (e: CancellationException) {
                opened.close()
                throw e
            } catch (e: MacRejectedException) {
                opened.close()
                if (e.error == ProtocolError.NOT_PAIRED) {
                    // The Mac no longer trusts this phone. Don't keep retrying.
                    store.clear()
                    _state.value = LinkState.NotPaired("${mac.name} no longer recognises this phone. Pair again.")
                    return false
                }
                onError(describe(e))
            } catch (e: Exception) {
                opened.close()
                onError(describe(e))
            }
        }
        return false
    }

    private fun candidates(mac: PairedMac): List<Pair<String, Int>> {
        val discovered = discovery.found.value.values
            .sortedByDescending { it.serviceName == mac.name }
            .map { it.host to it.port }
        val last = listOfNotNull(mac.lastHost?.let { it to mac.port })
        // Cap per round so spoofed announcements can't stall reconnecting (pinning still decides trust).
        return (discovered + last).distinct().take(MAX_CANDIDATES_PER_ROUND)
    }

    // ---- Connected session ----

    /** Runs a ready session until it ends. Returns the human-readable reason it ended. */
    private suspend fun runConnected(opened: MacSession, mac: PairedMac): String = coroutineScope {
        session = opened
        _state.value = LinkState.Connected(mac.name, opened.host, now())
        val heartbeat = launch {
            while (isActive) {
                delay(ConnectionTiming.PING_INTERVAL_MS)
                if (ConnectionTiming.isDead(opened.lastReceivedMs, now())) {
                    opened.close()
                    break
                }
                runCatching { opened.send(Message.Ping) }
            }
        }
        var reason = "Connection to ${mac.name} lost"
        try {
            for (envelope in opened.incoming) {
                when (val message = envelope.message) {
                    is Message.Ping -> runCatching { opened.send(Message.Pong(envelope.id)) }
                    is Message.Text -> appendChat(ChatLine(fromMac = true, text = message.text, atMs = now()))
                    is Message.Bye -> {
                        if (message.reason == "unpaired") {
                            store.clear()
                            _state.value = LinkState.NotPaired("${mac.name} removed this phone.")
                            linkJob?.cancel()
                        }
                        reason = "${mac.name} closed the connection"
                        break
                    }
                    is Message.Error -> Log.i(TAG, "Mac reported error ${message.code}")
                    else -> Unit // pong, unknown future messages: ignore
                }
            }
            if (ConnectionTiming.isDead(opened.lastReceivedMs, now())) {
                reason = "${mac.name} stopped responding"
            } else if (reason.startsWith("Connection to")) {
                opened.endReason?.let { reason = it }
            }
        } finally {
            heartbeat.cancel()
            opened.close()
            session = null
        }
        reason
    }

    // ---- Helpers ----

    /** Sends our hello, waits for the Mac's, and checks we share a protocol version. */
    private suspend fun handshakeHello(session: MacSession): Hello {
        session.send(Message.HelloMessage(Hello(phoneName, Hello.Platform.ANDROID, ProtocolVersion.SUPPORTED, APP_VERSION)))
        val first = withTimeout(HANDSHAKE_TIMEOUT_MS) { nextMeaningful(session) }
        val hello = (first.message as? Message.HelloMessage)?.hello
            ?: (first.message as? Message.Error)?.let { throw MacRejectedException(ProtocolError.fromWire(it.code), it.code) }
            ?: throw MacRejectedException(ProtocolError.MALFORMED, "expected hello")
        if (hello.platform != Hello.Platform.MAC) throw MacRejectedException(ProtocolError.MALFORMED, "not a Mac")
        ProtocolVersion.negotiate(ProtocolVersion.SUPPORTED, hello.versions)
            ?: throw MacRejectedException(ProtocolError.VERSION_UNSUPPORTED, "version_unsupported")
        return hello
    }

    /** Next envelope that isn't a ping/pong/unknown. Throws if the connection closes first. */
    private suspend fun nextMeaningful(session: MacSession): Envelope {
        for (envelope in session.incoming) {
            when (envelope.message) {
                is Message.Ping -> runCatching { session.send(Message.Pong(envelope.id)) }
                is Message.Pong, is Message.Unknown -> Unit
                else -> return envelope
            }
        }
        throw java.io.IOException("The Mac closed the connection")
    }

    private suspend fun refreshIdleState(paused: Boolean = false) {
        val mac = store.current()
        _state.update { current ->
            when {
                current is LinkState.Pairing -> current
                mac == null -> current as? LinkState.NotPaired ?: LinkState.NotPaired()
                paused -> LinkState.Paused(mac.name)
                current is LinkState.NotPaired -> LinkState.Paused(mac.name)
                else -> current
            }
        }
    }

    private suspend fun restartLinkIfStillPaired() {
        if (store.current() != null) startLink()
    }

    private fun appendChat(line: ChatLine) {
        _chat.update { (it + line).takeLast(MAX_CHAT_LINES) }
    }

    private fun describe(e: Exception): String = when (e) {
        is MacRejectedException -> e.error?.userMessage ?: "The Mac refused the connection (${e.message})."
        is javax.net.ssl.SSLHandshakeException -> "Secure connection failed. This may not be your paired Mac."
        is java.net.SocketTimeoutException -> "The Mac didn’t answer in time."
        is java.net.ConnectException, is java.net.NoRouteToHostException ->
            "Can’t reach the Mac. Check that M’AND is open on it and both are on the same Wi-Fi."
        is kotlinx.coroutines.TimeoutCancellationException -> "The Mac didn’t respond in time."
        else -> "Connection problem: ${e.javaClass.simpleName}"
    }

    private fun now() = System.currentTimeMillis()

    companion object {
        private const val TAG = "MandBridge"
        const val APP_VERSION = "0.1.0"
        private const val HANDSHAKE_TIMEOUT_MS = 10_000L
        private const val APPROVAL_TIMEOUT_MS = 5L * 60 * 1000
        private const val MAX_CHAT_LINES = 100
        private const val BYE_TIMEOUT_MS = 2_000L
        private const val MAX_CANDIDATES_PER_ROUND = 4

        @Volatile private var instance: BridgeClient? = null

        fun get(context: Context): BridgeClient =
            instance ?: synchronized(this) {
                instance ?: BridgeClient(context.applicationContext).also { instance = it }
            }
    }
}
