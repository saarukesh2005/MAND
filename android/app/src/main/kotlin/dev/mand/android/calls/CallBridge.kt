package dev.mand.android.calls

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.telecom.TelecomManager
import android.telephony.TelephonyCallback
import android.telephony.TelephonyManager
import android.util.Log
import dev.mand.android.data.FeatureSettings
import dev.mand.android.net.BridgeClient
import dev.mand.android.net.FeatureHandler
import dev.mand.core.Feature
import dev.mand.core.Message
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.util.concurrent.Executors

/**
 * Phone side of `calls.v1`: tells the Mac when the phone rings, and answers/declines on request.
 * Off by default; needs READ_PHONE_STATE (to see call state) and ANSWER_PHONE_CALLS (to act).
 * The call audio always stays on the phone. The caller's name comes from the dialer's own call
 * notification (via Notification access, if granted) — no contacts or call-log permission is used.
 */
class CallBridge(
    private val context: Context,
    private val client: BridgeClient,
    private val settings: FeatureSettings,
) : FeatureHandler {
    private val telephony = context.getSystemService(TelephonyManager::class.java)
    private val telecom = context.getSystemService(TelecomManager::class.java)
    private val executor = Executors.newSingleThreadExecutor()
    private var listening = false
    private val _lastResult = MutableStateFlow<String?>(null)
    val lastResult: StateFlow<String?> = _lastResult.asStateFlow()
    @Volatile private var current: Message.CallState = Message.CallState.IDLE

    private val callback = object : TelephonyCallback(), TelephonyCallback.CallStateListener {
        override fun onCallStateChanged(state: Int) {
            current = when (state) {
                TelephonyManager.CALL_STATE_RINGING -> Message.CallState.RINGING
                TelephonyManager.CALL_STATE_OFFHOOK -> Message.CallState.ACTIVE
                else -> Message.CallState.IDLE
            }
            if (current == Message.CallState.IDLE) callerName = null
            report()
        }
    }

    fun hasPermissions(): Boolean = PERMISSIONS.all { context.checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }

    /** Starts or stops watching call state to match the setting and permissions. Safe to call often. */
    @Synchronized
    fun refresh() {
        val wanted = settings.prefs.value.callsEnabled && hasPermissions()
        if (wanted && !listening) {
            runCatching { telephony.registerTelephonyCallback(executor, callback) }
                .onSuccess { listening = true }
                .onFailure { Log.w(TAG, "Couldn't watch call state: ${it.javaClass.simpleName}") }
        } else if (!wanted && listening) {
            telephony.unregisterTelephonyCallback(callback)
            listening = false
        }
    }

    override fun onConnected(macFeatures: Set<String>) {
        refresh()
        if (listening && current != Message.CallState.IDLE) report()
    }

    @SuppressLint("MissingPermission") // checked by hasPermissions()
    override fun onMessage(message: Message) {
        if (message !is Message.CallActionRequest) return
        if (!settings.prefs.value.callsEnabled || !hasPermissions()) {
            _lastResult.value = "Your Mac asked to ${message.action.wire} a call, but Calls on Mac is off."
            return
        }
        try {
            when (message.action) {
                Message.CallAction.ANSWER -> if (current == Message.CallState.RINGING) {
                    @Suppress("DEPRECATION") telecom.acceptRingingCall()
                }
                Message.CallAction.DECLINE -> {
                    @Suppress("DEPRECATION") telecom.endCall()
                }
            }
            _lastResult.value = null
        } catch (e: SecurityException) {
            _lastResult.value = "Android refused to ${message.action.wire} the call. Check M’AND’s Phone permission."
        }
    }

    private fun report() {
        if (!settings.prefs.value.callsEnabled || !client.macSupports(Feature.CALLS)) return
        val caller = if (current == Message.CallState.IDLE) null else callerName
        client.sendAsync(Message.CallStateUpdate(current, caller))
    }

    companion object {
        private const val TAG = "MandCalls"
        val PERMISSIONS = arrayOf(Manifest.permission.READ_PHONE_STATE, Manifest.permission.ANSWER_PHONE_CALLS)

        /** Set by the notification listener from the dialer's call notification (title = caller). */
        @Volatile var callerName: String? = null
    }
}
