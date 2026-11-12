package dev.mand.android.device

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.os.StatFs
import dev.mand.core.truncatedToUtf8Bytes
import dev.mand.android.net.BridgeClient
import dev.mand.android.net.FeatureHandler
import dev.mand.core.Feature
import dev.mand.core.Message

/** Sends real battery level and charging state to the Mac (`device.v1`) when connected and when they change. */
class BatteryReporter(private val context: Context, private val client: BridgeClient) : FeatureHandler {
    @Volatile private var last: Pair<Int, Boolean>? = null

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            read(intent)?.let { report(it, force = false) }
        }
    }

    fun start() {
        context.registerReceiver(receiver, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
    }

    override fun onConnected(macFeatures: Set<String>) {
        if (Feature.DEVICE !in macFeatures) return
        val sticky = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        sticky?.let(::read)?.let { report(it, force = true) }
        client.sendAsync(deviceInfo())
    }

    /** Model, Android version and free storage, so the Mac can show them in plain words. */
    private fun deviceInfo(): Message.DeviceInfo {
        val model = Build.MODEL.orEmpty()
        val maker = Build.MANUFACTURER.orEmpty().replaceFirstChar { it.titlecase() }
        val name = if (model.startsWith(maker, ignoreCase = true) || maker.isEmpty() || model.startsWith("Pixel")) model else "$maker $model"
        val stat = StatFs(Environment.getDataDirectory().path)
        return Message.DeviceInfo(
            model = name.ifBlank { "Android phone" }.truncatedToUtf8Bytes(Message.MAX_NAME_BYTES),
            os = "Android ${Build.VERSION.RELEASE}".truncatedToUtf8Bytes(64),
            storageFree = stat.availableBytes.coerceIn(0, Message.MAX_STORAGE_BYTES),
            storageTotal = stat.totalBytes.coerceIn(0, Message.MAX_STORAGE_BYTES),
        )
    }

    private fun report(status: Pair<Int, Boolean>, force: Boolean) {
        if (!force && status == last) return
        last = status
        if (client.macSupports(Feature.DEVICE)) client.sendAsync(Message.DeviceStatus(status.first, status.second))
    }

    private fun read(intent: Intent): Pair<Int, Boolean>? {
        val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
        val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
        if (level < 0 || scale <= 0) return null
        val status = intent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
        val charging = status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL
        return (level * 100 / scale).coerceIn(0, 100) to charging
    }
}
