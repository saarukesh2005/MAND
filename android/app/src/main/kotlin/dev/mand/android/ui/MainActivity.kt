package dev.mand.android.ui

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Bundle
import android.os.PowerManager
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import com.journeyapps.barcodescanner.ScanContract
import com.journeyapps.barcodescanner.ScanOptions
import dev.mand.android.data.PairedMacStore
import dev.mand.android.identity.KeystoreIdentity
import dev.mand.android.net.BridgeClient
import dev.mand.android.net.LinkState
import dev.mand.android.service.BridgeService
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainActivity : ComponentActivity() {
    private val client by lazy { BridgeClient.get(this) }
    private var permissions by mutableStateOf(PermissionStatus(notifications = false, batteryUnrestricted = false))
    private var phoneCode by mutableStateOf<String?>(null)

    private val notificationPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) {
        refreshPermissions()
    }

    private val scanner = registerForActivityResult(ScanContract()) { result ->
        result.contents?.let { text ->
            if (client.pair(text)) BridgeService.start(this)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        // First launch generates the Keystore key, which can take a moment — keep it off the main thread.
        lifecycleScope.launch {
            phoneCode = withContext(Dispatchers.Default) { KeystoreIdentity.fingerprint().shortDisplay }
        }

        setContent {
            MandTheme {
                HomeScreen(
                    client = client,
                    phoneSecurityCode = phoneCode,
                    permissions = permissions,
                    actions = HomeActions(
                        scanQr = ::launchScanner,
                        requestNotifications = { notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS) },
                        requestBatteryExemption = ::requestBatteryExemption,
                        resume = { BridgeService.start(this) },
                        pause = { BridgeService.stop(this) },
                    ),
                )
            }
        }

        // Reconnect automatically on launch if a Mac is already paired.
        lifecycleScope.launch {
            if (PairedMacStore(this@MainActivity).current() != null) BridgeService.start(this@MainActivity)
        }

        // Keep the background link running whenever a Mac is paired and the user hasn't paused it.
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                client.state.collect { state ->
                    if (state is LinkState.Searching || state is LinkState.Connected) BridgeService.start(this@MainActivity)
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        refreshPermissions()
    }

    private fun launchScanner() {
        scanner.launch(
            ScanOptions()
                .setDesiredBarcodeFormats(ScanOptions.QR_CODE)
                .setPrompt("Scan the QR code shown in M’AND on your Mac")
                .setBeepEnabled(false)
                .setOrientationLocked(false),
        )
    }

    /** Opens the system dialog; the user decides. Needed so Android doesn't cut the link in the background. */
    private fun requestBatteryExemption() {
        startActivity(
            Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName")),
        )
    }

    private fun refreshPermissions() {
        permissions = PermissionStatus(
            notifications = ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) ==
                PackageManager.PERMISSION_GRANTED,
            batteryUnrestricted = getSystemService(PowerManager::class.java).isIgnoringBatteryOptimizations(packageName),
        )
    }
}

data class PermissionStatus(val notifications: Boolean, val batteryUnrestricted: Boolean)

class HomeActions(
    val scanQr: () -> Unit,
    val requestNotifications: () -> Unit,
    val requestBatteryExemption: () -> Unit,
    val resume: () -> Unit,
    val pause: () -> Unit,
)
