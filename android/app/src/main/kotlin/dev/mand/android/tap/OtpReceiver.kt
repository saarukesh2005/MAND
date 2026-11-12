package dev.mand.android.tap

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.provider.Telephony
import dev.mand.android.MandApp
import dev.mand.core.Feature
import dev.mand.core.Message
import dev.mand.core.Otp

/** SMS one-time codes → the Mac's clipboard. Off unless the user turned it on (and granted SMS permission). */
class OtpReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return
        val app = context.applicationContext as MandApp
        if (!app.settings.prefs.value.otpToMac || !app.client.macSupports(Feature.CLIPBOARD)) return
        val text = Telephony.Sms.Intents.getMessagesFromIntent(intent).joinToString("") { it.messageBody ?: "" }
        val code = Otp.find(text) ?: return
        synchronized(sent) {
            val now = System.currentTimeMillis()
            sent.entries.removeAll { now - it.value > 120_000 }
            if (sent.put(code, now) != null) return // the same code twice (e.g. a resend) isn't sent again
        }
        app.client.sendAsync(Message.ClipboardText(code))
    }

    companion object {
        private val sent = HashMap<String, Long>()
    }
}
