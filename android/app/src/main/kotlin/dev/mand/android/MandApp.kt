package dev.mand.android

import android.app.Application
import dev.mand.android.calls.CallBridge
import dev.mand.android.clipboard.ClipboardBridge
import kotlinx.coroutines.launch
import dev.mand.android.data.FeatureSettings
import dev.mand.android.device.BatteryReporter
import dev.mand.android.files.FileTransferManager
import dev.mand.android.net.BridgeClient
import dev.mand.android.notify.NotificationBridge

/** Creates the connection and plugs in each feature module once per process. */
class MandApp : Application() {
    lateinit var client: BridgeClient
        private set
    lateinit var settings: FeatureSettings
        private set
    lateinit var files: FileTransferManager
        private set
    lateinit var clipboard: ClipboardBridge
        private set
    lateinit var notifications: NotificationBridge
        private set
    lateinit var calls: CallBridge
        private set
    lateinit var find: dev.mand.android.find.FindPhone
        private set
    lateinit var links: dev.mand.android.link.LinkBridge
        private set
    lateinit var remoteControl: dev.mand.android.screen.RemoteControl
        private set
    /** The connected Mac has Tap to Send switched on with a working sensor (from its `tap.ready`). */
    val tapMacReady = kotlinx.coroutines.flow.MutableStateFlow(false)

    override fun onCreate() {
        super.onCreate()
        client = BridgeClient.get(this)
        settings = FeatureSettings(this)
        files = FileTransferManager(this, client)
        clipboard = ClipboardBridge(this, client, settings)
        notifications = NotificationBridge(this)
        calls = CallBridge(this, client, settings)
        find = dev.mand.android.find.FindPhone(this, client)
        links = dev.mand.android.link.LinkBridge(this, client)
        remoteControl = dev.mand.android.screen.RemoteControl(this)
        val battery = BatteryReporter(this, client)
        listOf(files, clipboard, notifications, battery, calls, dev.mand.android.tap.TapBridge(this), find, links,
            dev.mand.android.screen.ScreenBridge(this), remoteControl)
            .forEach(client::register)
        battery.start()
        // Start watching call state once saved settings are loaded (only if the user turned it on).
        kotlinx.coroutines.MainScope().launch {
            settings.awaitLoaded()
            calls.refresh()
        }
    }
}
