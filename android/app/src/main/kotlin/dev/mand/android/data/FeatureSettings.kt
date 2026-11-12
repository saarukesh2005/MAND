package dev.mand.android.data

import android.content.Context
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringSetPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

/** What the user chose to share. Everything starts off: nothing is shared until switched on. */
data class FeaturePrefs(
    val clipboardEnabled: Boolean = false,
    val notificationsEnabled: Boolean = false,
    val allowedApps: Set<String> = emptySet(),
    val callsEnabled: Boolean = false,
    val onboardingDone: Boolean = false,
    /** SMS one-time codes go to the Mac's clipboard (off by default). */
    val otpToMac: Boolean = false,
    /** Tap to Send never flashes or captures while one of these apps is in front. */
    val tapPausedApps: Set<String> = DEFAULT_TAP_PAUSED,
) {
    companion object {
        /** UPI and banking apps (and anything showing money) start paused; the user can edit the list. */
        val DEFAULT_TAP_PAUSED = setOf(
            "in.org.npci.upiapp", // BHIM
            "com.google.android.apps.nbu.paisa.user", // Google Pay
            "com.phonepe.app", "net.one97.paytm", "com.dreamplug.androidapp", // PhonePe, Paytm, CRED
            "com.sbi.lotusintouch", "com.snapwork.hdfc", "com.csam.icici.bank.imobile", // SBI YONO, HDFC, ICICI
            "com.axis.mobile", "com.msf.kbank.mobile", // Axis, Kotak
        )
    }
}

private val Context.featureStore by preferencesDataStore(name = "mand_features")

class FeatureSettings(private val context: Context) {
    private object Keys {
        val CLIPBOARD = booleanPreferencesKey("clipboard_enabled")
        val NOTIFICATIONS = booleanPreferencesKey("notifications_enabled")
        val ALLOWED_APPS = stringSetPreferencesKey("notification_apps")
        val CALLS = booleanPreferencesKey("calls_enabled")
        val ONBOARDING_DONE = booleanPreferencesKey("onboarding_done")
        val OTP_TO_MAC = booleanPreferencesKey("otp_to_mac")
        val TAP_PAUSED = stringSetPreferencesKey("tap_paused_apps")
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val loaded = kotlinx.coroutines.CompletableDeferred<Unit>()
    private val _prefs = kotlinx.coroutines.flow.MutableStateFlow(FeaturePrefs())

    /** Always-current snapshot; readable from any thread (e.g. the notification listener). */
    val prefs: StateFlow<FeaturePrefs> = _prefs

    init {
        scope.launch {
            context.featureStore.data.collect { p ->
                _prefs.value = FeaturePrefs(
                    clipboardEnabled = p[Keys.CLIPBOARD] ?: false,
                    notificationsEnabled = p[Keys.NOTIFICATIONS] ?: false,
                    allowedApps = p[Keys.ALLOWED_APPS] ?: emptySet(),
                    callsEnabled = p[Keys.CALLS] ?: false,
                    onboardingDone = p[Keys.ONBOARDING_DONE] ?: false,
                    otpToMac = p[Keys.OTP_TO_MAC] ?: false,
                    tapPausedApps = p[Keys.TAP_PAUSED] ?: FeaturePrefs.DEFAULT_TAP_PAUSED,
                )
                loaded.complete(Unit) // only after the value above is visible
            }
        }
    }

    /** Suspends until the saved settings have been read (they start as all-off defaults). */
    suspend fun awaitLoaded() = loaded.await()

    fun setClipboard(enabled: Boolean) = edit { it[Keys.CLIPBOARD] = enabled }

    fun setCalls(enabled: Boolean) = edit { it[Keys.CALLS] = enabled }

    fun setOtpToMac(enabled: Boolean) = edit { it[Keys.OTP_TO_MAC] = enabled }

    fun setTapPaused(packageName: String, paused: Boolean) = edit { prefs ->
        val current = prefs[Keys.TAP_PAUSED] ?: FeaturePrefs.DEFAULT_TAP_PAUSED
        prefs[Keys.TAP_PAUSED] = if (paused) current + packageName else current - packageName
    }

    fun setOnboardingDone() = edit { it[Keys.ONBOARDING_DONE] = true }

    fun setNotifications(enabled: Boolean) = edit { it[Keys.NOTIFICATIONS] = enabled }

    fun setAppAllowed(packageName: String, allowed: Boolean) = edit { prefs ->
        val current = prefs[Keys.ALLOWED_APPS] ?: emptySet()
        prefs[Keys.ALLOWED_APPS] = if (allowed) current + packageName else current - packageName
    }

    private fun edit(change: (androidx.datastore.preferences.core.MutablePreferences) -> Unit) {
        scope.launch { context.featureStore.edit { change(it) } }
    }
}
