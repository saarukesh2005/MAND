package dev.mand.android.screen

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import dev.mand.android.R
import dev.mand.android.net.FeatureHandler
import dev.mand.core.Message

/** The Mac asked to see the screen: show a notification; tapping it opens Android's "Start now" prompt. */
class ScreenBridge(private val context: Context) : FeatureHandler {
    override fun onMessage(message: Message) {
        when (message) {
            Message.ScreenRequest -> askToShare()
            is Message.ScreenStop -> {
                cancelAsk()
                ScreenShareService.stop(context)
            }
            else -> Unit
        }
    }

    override fun onDisconnected() {
        cancelAsk()
    }

    private fun askToShare() {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, context.getString(R.string.channel_screen_ask), NotificationManager.IMPORTANCE_HIGH),
        )
        val open = PendingIntent.getActivity(
            context, 0, Intent(context, ScreenShareActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val notification = Notification.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(context.getString(R.string.screen_ask_title))
            .setContentText(context.getString(R.string.screen_ask_text))
            .setContentIntent(open)
            .setAutoCancel(true)
            .setTimeoutAfter(ASK_TIMEOUT_MS)
            .build()
        runCatching { manager.notify(NOTIFICATION_ID, notification) }
    }

    private fun cancelAsk() {
        context.getSystemService(NotificationManager::class.java).cancel(NOTIFICATION_ID)
    }

    private companion object {
        const val CHANNEL_ID = "mand_screen_ask"
        const val NOTIFICATION_ID = 4202
        const val ASK_TIMEOUT_MS = 60_000L
    }
}
