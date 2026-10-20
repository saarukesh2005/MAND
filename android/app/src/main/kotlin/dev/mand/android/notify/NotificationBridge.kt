package dev.mand.android.notify

import android.content.ComponentName
import android.content.Context
import android.provider.Settings
import dev.mand.android.net.FeatureHandler
import dev.mand.core.Message

/** Handles the Mac's `notification.dismiss` and reports whether Notification Access is granted. */
class NotificationBridge(private val context: Context) : FeatureHandler {
    override fun onMessage(message: Message) {
        if (message is Message.NotificationDismiss) NotificationMirrorService.dismiss(message.key)
    }

    fun hasAccess(): Boolean {
        val enabled = Settings.Secure.getString(context.contentResolver, "enabled_notification_listeners") ?: return false
        val me = ComponentName(context, NotificationMirrorService::class.java)
        return enabled.split(':').any { ComponentName.unflattenFromString(it) == me }
    }
}
