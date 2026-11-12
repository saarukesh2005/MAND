package dev.mand.android.ui

import android.Manifest
import android.content.ComponentName
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
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import com.journeyapps.barcodescanner.ScanContract
import com.journeyapps.barcodescanner.ScanOptions
import dev.mand.android.MandApp
import dev.mand.android.calls.CallBridge
import dev.mand.android.data.PairedMacStore
import dev.mand.android.identity.KeystoreIdentity
import dev.mand.android.net.LinkState
import dev.mand.android.notify.NotificationMirrorService
import dev.mand.android.service.BridgeService
import dev.mand.android.system.LocalNetworkAccess
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class MainActivity : ComponentActivity() {
    private val app get() = application as MandApp
    private val client get() = app.client
    private var permissions by mutableStateOf(PermissionStatus(notifications = false, batteryUnrestricted = false))
    private var notificationAccess by mutableStateOf(false)
    private var tapEnabled by mutableStateOf(false)
    private var pendingSmsResult: ((Boolean) -> Unit)? = null

    private val smsPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        pendingSmsResult?.invoke(granted)
        pendingSmsResult = null
    }
    private var phoneCode by mutableStateOf<String?>(null)
    /** Set when pairing was asked for before Android's "find devices" permission; pairing continues once it's allowed. */
    private var pairAfterPermission = false
    private var scanProblem by mutableStateOf<String?>(null)
    private var pendingCallResult: ((Boolean) -> Unit)? = null

    private val notificationPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) {
        refreshPermissions()
    }

    private val localNetworkPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) {
            client.retryNow()
            if (pairAfterPermission) {
                pairAfterPermission = false
                launchScanner()
            }
        } else if (!shouldShowRequestPermissionRationale(LocalNetworkAccess.PERMISSION)) {
            openAppSettings() // the user chose "Don't ask again"; the only way back is Settings
        }
    }

    private val callPermissions = registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { result ->
        val granted = CallBridge.PERMISSIONS.all { result[it] == true || checkSelfPermission(it) == PackageManager.PERMISSION_GRANTED }
        pendingCallResult?.invoke(granted)
        pendingCallResult = null
        app.calls.refresh()
    }

    private val filePicker = registerForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris ->
        if (uris.isNotEmpty()) lifecycleScope.launch { app.files.importAndSend(uris) }
    }

    private val scanner = registerForActivityResult(ScanContract()) { result ->
        result.contents?.let { text ->
            if (client.pair(text)) {
                BridgeService.start(this)
            } else {
                scanProblem = "That isn’t an M’AND code. On your Mac, open M’AND and click “Pair a Phone”, then scan the code shown there."
            }
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
                val prefs by app.settings.prefs.collectAsStateWithLifecycle()
                val state by client.state.collectAsStateWithLifecycle()
                if (!prefs.onboardingDone && state is LinkState.NotPaired) {
                    OnboardingScreen(
                        needsLocalNetwork = LocalNetworkAccess.isRequired && !LocalNetworkAccess.isGranted(this),
                        requestLocalNetwork = {
                            app.settings.setOnboardingDone()
                            pairAfterPermission = true
                            requestLocalNetwork()
                        },
                        onFinish = { pairNow ->
                            app.settings.setOnboardingDone()
                            if (pairNow) launchScanner()
                        },
                    )
                } else {
                    HomeScreen(
                        client = client,
                        phoneSecurityCode = phoneCode,
                        permissions = permissions,
                        actions = HomeActions(
                            scanQr = ::launchScanner,
                            requestNotifications = { notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS) },
                            requestBatteryExemption = ::requestBatteryExemption,
                            requestLocalNetwork = ::requestLocalNetwork,
                            resume = { BridgeService.start(this) },
                            pause = { BridgeService.stop(this) },
                            retry = client::retryNow,
                        ),
                        features = { connected ->
                            FeatureCards(
                                app = app,
                                connected = connected,
                                notificationAccess = notificationAccess,
                                actions = FeatureActions(
                                    pickFiles = { filePicker.launch(arrayOf("*/*")) },
                                    openNotificationAccess = ::openNotificationAccess,
                                    requestCallPermissions = ::requestCallPermissions,
                                    openAccessibility = {
                                        startActivity(Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
                                    },
                                    openAppSettings = ::openAppSettings,
                                    requestSms = { onResult ->
                                        if (checkSelfPermission(Manifest.permission.RECEIVE_SMS) == PackageManager.PERMISSION_GRANTED) {
                                            onResult(true)
                                        } else {
                                            pendingSmsResult = onResult
                                            smsPermission.launch(Manifest.permission.RECEIVE_SMS)
                                        }
                                    },
                                ),
                                tapEnabled = tapEnabled,
                            )
                        },
                    )
                }
                scanProblem?.let { problem ->
                    androidx.compose.material3.AlertDialog(
                        onDismissRequest = { scanProblem = null },
                        title = { androidx.compose.material3.Text("Couldn’t pair") },
                        text = { androidx.compose.material3.Text(problem) },
                        confirmButton = {
                            androidx.compose.material3.TextButton(onClick = { scanProblem = null; launchScanner() }) {
                                androidx.compose.material3.Text("Scan again")
                            }
                        },
                        dismissButton = {
                            androidx.compose.material3.TextButton(onClick = { scanProblem = null }) {
                                androidx.compose.material3.Text("Cancel")
                            }
                        },
                    )
                }
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
                    if (state is LinkState.Searching || state is LinkState.Connected || state is LinkState.Offline) {
                        BridgeService.start(this@MainActivity)
                    }
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        refreshPermissions()
        // Coming back from Settings after granting something: try again straight away.
        if (LocalNetworkAccess.isGranted(this)) client.retryNow()
        app.calls.refresh()
    }

    private fun launchScanner() {
        if (!LocalNetworkAccess.isGranted(this)) {
            pairAfterPermission = true
            requestLocalNetwork()
            return
        }
        scanner.launch(
            ScanOptions()
                .setDesiredBarcodeFormats(ScanOptions.QR_CODE)
                .setPrompt("Scan the QR code shown in M’AND on your Mac")
                .setBeepEnabled(false)
                .setOrientationLocked(false),
        )
    }

    private fun requestLocalNetwork() {
        if (LocalNetworkAccess.isRequired) localNetworkPermission.launch(LocalNetworkAccess.PERMISSION)
    }

    private fun requestCallPermissions(onResult: (Boolean) -> Unit) {
        if (app.calls.hasPermissions()) {
            onResult(true)
            app.calls.refresh()
            return
        }
        pendingCallResult = onResult
        callPermissions.launch(CallBridge.PERMISSIONS)
    }

    /** Opens the system dialog; the user decides. Needed so Android doesn't cut the link in the background. */
    private fun requestBatteryExemption() {
        startActivity(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName")))
    }

    private fun openAppSettings() {
        startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
    }

    private fun openNotificationAccess() {
        val detail = Intent(Settings.ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS).putExtra(
            Settings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME,
            ComponentName(this, NotificationMirrorService::class.java).flattenToString(),
        )
        runCatching { startActivity(detail) }.onFailure { startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)) }
    }

    private fun refreshPermissions() {
        notificationAccess = app.notifications.hasAccess()
        tapEnabled = dev.mand.android.tap.TapService.isEnabled(this)
        permissions = PermissionStatus(
            notifications = checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED,
            batteryUnrestricted = getSystemService(PowerManager::class.java).isIgnoringBatteryOptimizations(packageName),
        )
    }
}
