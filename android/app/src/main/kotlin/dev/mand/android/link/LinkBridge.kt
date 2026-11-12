package dev.mand.android.link

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import dev.mand.android.R
import dev.mand.android.net.BridgeClient
import dev.mand.android.net.FeatureHandler
import dev.mand.core.Feature
import dev.mand.core.LinkRules
import dev.mand.core.Message
import dev.mand.core.truncatedToUtf8Bytes

/**
 * Web links between the devices (`link.v1`). From the Mac: a notification that opens the page when tapped
 * (Android doesn't let apps open pages from the background). To the Mac: links shared to M’AND open there.
 */
class LinkBridge(private val context: Context, private val client: BridgeClient) : FeatureHandler {
    override fun onMessage(message: Message) {
        if (message is Message.LinkOpen) showLink(message.url, message.title)
    }

    /** Sends a web link to the Mac; false if it isn't a web link or the Mac can't take links. */
    fun send(url: String, title: String?): Boolean {
        if (!LinkRules.isValid(url) || !client.macSupports(Feature.LINK)) return false
        client.sendAsync(Message.LinkOpen(url, title?.trim()?.takeIf { it.isNotEmpty() }?.truncatedToUtf8Bytes(LinkRules.MAX_TITLE_BYTES)))
        return true
    }

    private fun showLink(url: String, title: String?) {
        // The codec already accepts only http(s) links; check again before handing it to the system.
        val uri = Uri.parse(url)
        if (!LinkRules.isValid(url) || uri.scheme?.lowercase() !in setOf("http", "https")) return
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, context.getString(R.string.channel_links), NotificationManager.IMPORTANCE_HIGH),
        )
        val view = Intent(Intent.ACTION_VIEW, uri).addCategory(Intent.CATEGORY_BROWSABLE)
        val open = PendingIntent.getActivity(context, url.hashCode(), view, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val notification = Notification.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(context.getString(R.string.link_title))
            .setContentText(title ?: uri.host ?: url)
            .setSubText(uri.host)
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        runCatching { manager.notify(url.hashCode(), notification) }
    }

    private companion object {
        const val CHANNEL_ID = "mand_links"
    }
}
