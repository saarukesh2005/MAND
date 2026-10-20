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
)

private val Context.featureStore by preferencesDataStore(name = "mand_features")

class FeatureSettings(private val context: Context) {
    private object Keys {
        val CLIPBOARD = booleanPreferencesKey("clipboard_enabled")
        val NOTIFICATIONS = booleanPreferencesKey("notifications_enabled")
        val ALLOWED_APPS = stringSetPreferencesKey("notification_apps")
        val CALLS = booleanPreferencesKey("calls_enabled")
        val ONBOARDING_DONE = booleanPreferencesKey("onboarding_done")
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
                )
                loaded.complete(Unit) // only after the value above is visible
            }
        }
    }

    /** Suspends until the saved settings have been read (they start as all-off defaults). */
    suspend fun awaitLoaded() = loaded.await()

    fun setClipboard(enabled: Boolean) = edit { it[Keys.CLIPBOARD] = enabled }

    fun setCalls(enabled: Boolean) = edit { it[Keys.CALLS] = enabled }

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
