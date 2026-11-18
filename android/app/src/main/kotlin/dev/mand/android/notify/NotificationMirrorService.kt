package dev.mand.android.notify

import android.app.Notification
import android.app.RemoteInput
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
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
        // The dialer's incoming-call notification carries the caller's name; Calls on Mac uses it.
        if (sbn.notification.category == Notification.CATEGORY_CALL) {
            sbn.notification.extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.takeIf { it.isNotBlank() }
                ?.let { dev.mand.android.calls.CallBridge.callerName = it.truncatedToUtf8Bytes(128) }
        }
        val message = toMessage(sbn) ?: return
        rememberSent(sbn.key)
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
            canReply = replyAction(sbn.notification) != null,
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

        private const val MAX_REMEMBERED = 500
        private val sentKeys = java.util.Collections.synchronizedSet(LinkedHashSet<String>())

        private fun rememberSent(key: String) {
            synchronized(sentKeys) {
                sentKeys.remove(key)
                sentKeys.add(key)
                while (sentKeys.size > MAX_REMEMBERED) sentKeys.remove(sentKeys.first())
            }
        }

        /** Dismisses a notification on the phone when the user dismisses it on the Mac — only ones M’AND shared. */
        fun dismiss(key: String) {
            if (!sentKeys.remove(key)) return
            runCatching { instance?.cancelNotification(key) }
        }

        /**
         * The app's own "Reply" action, if it has one: an action carrying a [RemoteInput] is what the phone's
         * notification shade types into. Returns null when the app offers no reply box (most notifications).
         */
        private fun replyAction(notification: Notification): Notification.Action? =
            notification.actions?.firstOrNull { action ->
                action.actionIntent != null && action.remoteInputs?.any { !it.resultKey.isNullOrEmpty() } == true
            }

        /**
         * Answers a notification from the Mac by filling in the app's own reply box and firing its action —
         * the same path as typing in the shade, so the app sends the message itself. Only notifications
         * M’AND actually shared can be answered, and the Mac is told what happened either way.
         */
        fun reply(key: String, text: String) {
            val service = instance
            val app = service?.application as? MandApp
            fun tell(ok: Boolean, why: String?) {
                app?.client?.sendAsync(Message.NotificationReplied(key, ok, why))
            }
            if (service == null) return tell(false, "off")
            if (key !in sentKeys) return tell(false, "unknown")

            val sbn = runCatching { service.activeNotifications }.getOrNull()?.firstOrNull { it.key == key }
                ?: return tell(false, "gone")
            val action = replyAction(sbn.notification) ?: return tell(false, "no-reply-box")
            val inputs = action.remoteInputs?.filter { !it.resultKey.isNullOrEmpty() }.orEmpty()
            if (inputs.isEmpty()) return tell(false, "no-reply-box")

            val outcome = runCatching {
                val filled = Bundle().apply { inputs.forEach { putCharSequence(it.resultKey, text) } }
                val intent = Intent().apply {
                    RemoteInput.addResultsToIntent(inputs.toTypedArray(), this, filled)
                    // Mark it as typed by a person, so apps that check don't treat it as a bot reply.
                    RemoteInput.setResultsSource(this, RemoteInput.SOURCE_FREE_FORM_INPUT)
                }
                action.actionIntent.send(service, 0, intent)
            }
            if (outcome.isSuccess) tell(true, null) else tell(false, "send-failed")
        }
    }
}
