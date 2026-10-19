package dev.mand.android.net

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.util.Log
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.net.Inet4Address
import java.util.concurrent.Executors

/** A Mac advertising `_mand._tcp` on the local network. Identity is still checked by TLS pinning. */
data class DiscoveredMac(val serviceName: String, val host: String, val port: Int)

/**
 * Finds M’AND Macs with Bonjour/mDNS (Android NSD). Discovery only suggests addresses;
 * a found Mac is trusted only if its certificate matches the paired fingerprint.
 */
class MacDiscovery(context: Context) {
    private val nsd = context.getSystemService(NsdManager::class.java)
    private val executor = Executors.newSingleThreadExecutor()
    private val callbacks = mutableMapOf<String, NsdManager.ServiceInfoCallback>()
    private val _found = MutableStateFlow<Map<String, DiscoveredMac>>(emptyMap())
    val found: StateFlow<Map<String, DiscoveredMac>> = _found.asStateFlow()
    private var listener: NsdManager.DiscoveryListener? = null

    @Synchronized
    fun start() {
        if (listener != null) return
        val newListener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(serviceType: String) = Unit
            override fun onDiscoveryStopped(serviceType: String) = Unit
            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                Log.w(TAG, "Discovery failed to start ($errorCode)")
                synchronized(this@MacDiscovery) { listener = null }
            }
            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) = Unit
            override fun onServiceFound(info: NsdServiceInfo) = watch(info)
            override fun onServiceLost(info: NsdServiceInfo) = unwatch(info.serviceName)
        }
        listener = newListener
        nsd.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, newListener)
    }

    @Synchronized
    fun stop() {
        listener?.let { runCatching { nsd.stopServiceDiscovery(it) } }
        listener = null
        callbacks.values.forEach { runCatching { nsd.unregisterServiceInfoCallback(it) } }
        callbacks.clear()
        _found.value = emptyMap()
    }

    @Synchronized
    private fun watch(info: NsdServiceInfo) {
        val name = info.serviceName
        if (callbacks.containsKey(name)) return
        val callback = object : NsdManager.ServiceInfoCallback {
            override fun onServiceInfoCallbackRegistrationFailed(errorCode: Int) = Unit
            override fun onServiceUpdated(updated: NsdServiceInfo) {
                val host = updated.hostAddresses.firstOrNull { it is Inet4Address }?.hostAddress ?: return
                _found.value = _found.value + (name to DiscoveredMac(name, host, updated.port))
            }
            override fun onServiceLost() {
                _found.value = _found.value - name
            }
            override fun onServiceInfoCallbackUnregistered() = Unit
        }
        callbacks[name] = callback
        nsd.registerServiceInfoCallback(info, executor, callback)
    }

    @Synchronized
    private fun unwatch(name: String) {
        callbacks.remove(name)?.let { runCatching { nsd.unregisterServiceInfoCallback(it) } }
        _found.value = _found.value - name
    }

    companion object {
        private const val TAG = "MandDiscovery"
        const val SERVICE_TYPE = "_mand._tcp"
    }
}
