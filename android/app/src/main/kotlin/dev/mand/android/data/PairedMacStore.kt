package dev.mand.android.data

import android.content.Context
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import dev.mand.core.Fingerprint
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

/** The Mac this phone is paired with. The fingerprint is public (not a secret), so DataStore is fine. */
data class PairedMac(
    val fingerprint: Fingerprint,
    val name: String,
    val lastHost: String?,
    val port: Int,
)

private val Context.dataStore by preferencesDataStore(name = "mand_pairing")

class PairedMacStore(private val context: Context) {
    private object Keys {
        val FINGERPRINT = stringPreferencesKey("mac_fingerprint")
        val NAME = stringPreferencesKey("mac_name")
        val HOST = stringPreferencesKey("mac_last_host")
        val PORT = intPreferencesKey("mac_port")
    }

    val pairedMac: Flow<PairedMac?> = context.dataStore.data.map { prefs ->
        val fingerprint = prefs[Keys.FINGERPRINT]?.let(Fingerprint::fromHex) ?: return@map null
        PairedMac(
            fingerprint = fingerprint,
            name = prefs[Keys.NAME] ?: "Mac",
            lastHost = prefs[Keys.HOST],
            port = prefs[Keys.PORT] ?: DEFAULT_PORT,
        )
    }

    suspend fun current(): PairedMac? = pairedMac.first()

    suspend fun save(mac: PairedMac) {
        context.dataStore.edit { prefs ->
            prefs[Keys.FINGERPRINT] = mac.fingerprint.hex
            prefs[Keys.NAME] = mac.name
            prefs[Keys.PORT] = mac.port
            mac.lastHost?.let { prefs[Keys.HOST] = it } ?: prefs.remove(Keys.HOST)
        }
    }

    suspend fun clear() {
        context.dataStore.edit { it.clear() }
    }

    companion object {
        const val DEFAULT_PORT = 47821
    }
}
