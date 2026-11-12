package dev.mand.android.find

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.VibratorManager
import android.util.Log
import dev.mand.android.MandApp
import dev.mand.android.R
import dev.mand.android.net.BridgeClient
import dev.mand.android.net.FeatureHandler
import dev.mand.android.ui.MainActivity
import dev.mand.core.Feature
import dev.mand.core.Message

/**
 * "Find my phone" (`find.v1`): plays the alarm sound at full alarm volume (so it's heard even on silent),
 * vibrates, and shows a notification. Stops on Stop (Mac or notification), when M’AND is opened, or after a minute.
 */
class FindPhone(private val context: Context, private val client: BridgeClient) : FeatureHandler {
    private val main = Handler(Looper.getMainLooper())
    private var player: MediaPlayer? = null
    private var savedAlarmVolume: Int? = null
    private val audio get() = context.getSystemService(AudioManager::class.java)
    private val stopLater = Runnable { stop() }

    val isRinging: Boolean get() = player != null

    override fun onMessage(message: Message) {
        when (message) {
            Message.FindRing -> main.post { start() }
            Message.FindStop -> main.post { stop() }
            else -> Unit
        }
    }

    fun start() {
        if (player != null) return
        savedAlarmVolume = audio.getStreamVolume(AudioManager.STREAM_ALARM)
        runCatching { audio.setStreamVolume(AudioManager.STREAM_ALARM, audio.getStreamMaxVolume(AudioManager.STREAM_ALARM), 0) }
        val sound = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
        player = runCatching {
            MediaPlayer().apply {
                setAudioAttributes(
                    AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build(),
                )
                setDataSource(context, sound)
                isLooping = true
                prepare()
                start()
            }
        }.onFailure { Log.w(TAG, "Couldn't play the find sound", it) }.getOrNull()
        vibrate()
        showNotification()
        main.postDelayed(stopLater, RING_MS)
        report(true)
    }

    fun stop() {
        main.removeCallbacks(stopLater)
        val wasRinging = player != null
        player?.let { runCatching { it.stop() }; it.release() }
        player = null
        savedAlarmVolume?.let { runCatching { audio.setStreamVolume(AudioManager.STREAM_ALARM, it, 0) } }
        savedAlarmVolume = null
        context.getSystemService(VibratorManager::class.java).defaultVibrator.cancel()
        context.getSystemService(NotificationManager::class.java).cancel(NOTIFICATION_ID)
        if (wasRinging) report(false)
    }

    private fun report(ringing: Boolean) {
        if (client.macSupports(Feature.FIND)) client.sendAsync(Message.FindState(ringing))
    }

    private fun vibrate() {
        val pattern = longArrayOf(0, 800, 400)
        runCatching {
            context.getSystemService(VibratorManager::class.java).defaultVibrator
                .vibrate(VibrationEffect.createWaveform(pattern, 0))
        }
    }

    private fun showNotification() {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, context.getString(R.string.channel_find), NotificationManager.IMPORTANCE_HIGH),
        )
        val flags = PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        val open = PendingIntent.getActivity(context, 0, Intent(context, MainActivity::class.java), flags)
        val stop = PendingIntent.getBroadcast(context, 0, Intent(context, StopReceiver::class.java), flags)
        val notification = Notification.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(context.getString(R.string.find_title))
            .setContentText(context.getString(R.string.find_text))
            .setContentIntent(open)
            .setDeleteIntent(stop)
            .setCategory(Notification.CATEGORY_ALARM)
            .addAction(Notification.Action.Builder(null, context.getString(R.string.find_stop), stop).build())
            .build()
        runCatching { manager.notify(NOTIFICATION_ID, notification) } // may be refused if notifications are off
    }

    /** The notification's Stop button (and swiping it away). */
    class StopReceiver : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            (context.applicationContext as MandApp).find.stop()
        }
    }

    private companion object {
        const val TAG = "MandFind"
        const val CHANNEL_ID = "mand_find"
        const val NOTIFICATION_ID = 4101
        const val RING_MS = 60_000L
    }
}
