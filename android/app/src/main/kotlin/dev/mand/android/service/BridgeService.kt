package dev.mand.android.service

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import androidx.lifecycle.LifecycleService
import androidx.lifecycle.lifecycleScope
import dev.mand.android.R
import dev.mand.android.net.BridgeClient
import dev.mand.android.net.LinkState
import dev.mand.android.ui.MainActivity
import kotlinx.coroutines.launch

/**
 * Keeps the link to the Mac alive while the app is in the background, using the
 * `connectedDevice` foreground-service type (allowed for a persistent link to a paired computer).
 * The status notification is required by Android and shows what M’AND is doing.
 */
class BridgeService : LifecycleService() {
    private val client by lazy { BridgeClient.get(this) }

    override fun onCreate() {
        super.onCreate()
        ensureChannel()
        startForeground(NOTIFICATION_ID, buildNotification(client.state.value), ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
        lifecycleScope.launch {
            var wasActive = false
            client.state.collect { state ->
                val active = state is LinkState.Connected || state is LinkState.Searching || state is LinkState.Pairing
                if (active) {
                    wasActive = true
                    getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, buildNotification(state))
                } else if (wasActive) {
                    // Unpaired, forgotten or paused: no reason to keep a background service and notification.
                    stopSelf()
                }
            }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        super.onStartCommand(intent, flags, startId)
        if (intent?.action == ACTION_STOP) {
            client.stopLink()
            stopSelf()
            return START_NOT_STICKY
        }
        client.startLink()
        return START_STICKY
    }

    override fun onDestroy() {
        client.stopLink()
        super.onDestroy()
    }

    private fun ensureChannel() {
        val channel = NotificationChannel(CHANNEL_ID, getString(R.string.channel_status), NotificationManager.IMPORTANCE_LOW)
            .apply { description = getString(R.string.channel_status_description) }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private fun buildNotification(state: LinkState): Notification {
        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE,
        )
        val stop = PendingIntent.getService(
            this, 1, Intent(this, BridgeService::class.java).setAction(ACTION_STOP), PendingIntent.FLAG_IMMUTABLE,
        )
        val text = when (state) {
            is LinkState.Connected -> "Connected to ${state.macName}"
            is LinkState.Searching -> "Looking for ${state.macName}…"
            is LinkState.Pairing -> "Pairing with ${state.macName}…"
            is LinkState.Paused -> "Paused"
            is LinkState.NotPaired -> "Not paired"
        }
        return Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(getString(R.string.app_name))
            .setContentText(text)
            .setContentIntent(open)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(Notification.CATEGORY_SERVICE)
            .addAction(Notification.Action.Builder(null, "Stop", stop).build())
            .build()
    }

    companion object {
        private const val CHANNEL_ID = "mand_status"
        private const val NOTIFICATION_ID = 1
        private const val ACTION_STOP = "dev.mand.android.STOP"

        fun start(context: Context) {
            context.startForegroundService(Intent(context, BridgeService::class.java))
        }

        fun stop(context: Context) {
            context.startService(Intent(context, BridgeService::class.java).setAction(ACTION_STOP))
        }
    }
}
