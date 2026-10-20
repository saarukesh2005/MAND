package dev.mand.android

import android.app.Application
import dev.mand.android.clipboard.ClipboardBridge
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

    override fun onCreate() {
        super.onCreate()
        client = BridgeClient.get(this)
        settings = FeatureSettings(this)
        files = FileTransferManager(this, client)
        clipboard = ClipboardBridge(this, client, settings)
        notifications = NotificationBridge(this)
        val battery = BatteryReporter(this, client)
        listOf(files, clipboard, notifications, battery).forEach(client::register)
        battery.start()
    }
}
