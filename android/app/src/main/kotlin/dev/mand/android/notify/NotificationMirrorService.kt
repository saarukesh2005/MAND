package dev.mand.android.notify

import android.app.Notification
import android.content.pm.PackageManager
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import dev.mand.android.MandApp
import dev.mand.core.Feature
import dev.mand.core.Message
import dev.mand.core.truncatedToUtf8Bytes

/**
 * Forwards notifications from apps the user allowed to the Mac (`notifications.v1`).
 * Android only runs this after the user grants Notification Access in Settings.
 * Ongoing (e.g. music, navigation) and group-summary notifications are skipped.
 */
class NotificationMirrorService : NotificationListenerService() {
    private val app get() = application as MandApp

    override fun onListenerConnected() {
        super.onListenerConnected()
        instance = this
    }

    override fun onListenerDisconnected() {
        if (instance === this) instance = null
        super.onListenerDisconnected()
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val message = toMessage(sbn) ?: return
        app.client.sendAsync(message)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        if (!shouldShare(sbn) || sbn.key.toByteArray().size > MAX_KEY_BYTES) return
        app.client.sendAsync(Message.NotificationRemoved(sbn.key))
    }

    private fun shouldShare(sbn: StatusBarNotification): Boolean {
        val prefs = app.settings.prefs.value
        if (!prefs.notificationsEnabled || sbn.packageName !in prefs.allowedApps) return false
        if (sbn.packageName == packageName || sbn.isOngoing) return false
        if (sbn.notification.flags and Notification.FLAG_GROUP_SUMMARY != 0) return false
        return app.client.macSupports(Feature.NOTIFICATIONS)
    }

    private fun toMessage(sbn: StatusBarNotification): Message.NotificationPosted? {
        if (!shouldShare(sbn) || sbn.key.toByteArray().size > MAX_KEY_BYTES) return null
        val extras = sbn.notification.extras
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()
        val text = (extras.getCharSequence(Notification.EXTRA_BIG_TEXT) ?: extras.getCharSequence(Notification.EXTRA_TEXT))
            ?.toString()
        if (title.isNullOrBlank() && text.isNullOrBlank()) return null
        return Message.NotificationPosted(
            key = sbn.key,
            app = sbn.packageName.truncatedToUtf8Bytes(256),
            appName = appLabel(sbn.packageName).truncatedToUtf8Bytes(128).ifEmpty { "App" },
            title = title?.takeIf { it.isNotBlank() }?.truncatedToUtf8Bytes(512),
            text = text?.takeIf { it.isNotBlank() }?.truncatedToUtf8Bytes(4_096),
            time = sbn.postTime,
        )
    }

    private fun appLabel(packageName: String): String = runCatching {
        packageManager.getApplicationLabel(packageManager.getApplicationInfo(packageName, PackageManager.ApplicationInfoFlags.of(0)))
            .toString()
    }.getOrDefault(packageName)

    companion object {
        private const val MAX_KEY_BYTES = 256

        @Volatile var instance: NotificationMirrorService? = null
            private set

        /** Dismisses a notification on the phone when the user dismisses it on the Mac. */
        fun dismiss(key: String) {
            runCatching { instance?.cancelNotification(key) }
        }
    }
}
