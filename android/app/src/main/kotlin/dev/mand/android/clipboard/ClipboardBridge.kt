package dev.mand.android.clipboard

import android.content.ClipData
import android.content.ClipDescription
import android.content.ClipboardManager
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.PersistableBundle
import dev.mand.android.data.FeatureSettings
import dev.mand.android.net.BridgeClient
import dev.mand.android.net.FeatureHandler
import dev.mand.core.Feature
import dev.mand.core.Message
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Phone side of `clipboard.v1`. Android only lets the app on screen read the clipboard, so sending
 * always comes from a deliberate action (the app, the share sheet, or the Quick Settings tile).
 */
class ClipboardBridge(
    private val context: Context,
    private val client: BridgeClient,
    private val settings: FeatureSettings,
) : FeatureHandler {
    enum class Result { SENT, DISABLED, NOT_CONNECTED, EMPTY, SENSITIVE, TOO_LARGE }

    private val clipboard get() = context.getSystemService(ClipboardManager::class.java)
    private val main = Handler(Looper.getMainLooper())
    private val _notice = MutableStateFlow<String?>(null)
    val notice: StateFlow<String?> = _notice.asStateFlow()

    /** Text from the Mac goes onto the phone clipboard, if the user turned sharing on. */
    override fun onMessage(message: Message) {
        if (message !is Message.ClipboardText || !settings.prefs.value.clipboardEnabled) return
        main.post {
            clipboard.setPrimaryClip(ClipData.newPlainText("From Mac", message.text))
            _notice.value = "Copied text from your Mac."
        }
    }

    /** Must be called while an M’AND screen has focus (Android blocks background clipboard reads). */
    fun sendCurrentClip(): Result {
        val clip = clipboard.primaryClip
        val text = clip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.coerceToText(context)?.toString()
        return sendText(text, isSensitive(clip?.description?.extras))
    }

    /** Sends text the user shared to M’AND (or read from the clipboard). */
    fun sendText(text: String?, sensitive: Boolean = false): Result {
        val result = when {
            !settings.prefs.value.clipboardEnabled -> Result.DISABLED
            !client.macSupports(Feature.CLIPBOARD) -> Result.NOT_CONNECTED
            sensitive -> Result.SENSITIVE
            text.isNullOrEmpty() -> Result.EMPTY
            text.toByteArray().size > Message.MAX_CLIPBOARD_BYTES -> Result.TOO_LARGE
            else -> {
                client.sendAsync(Message.ClipboardText(text))
                Result.SENT
            }
        }
        _notice.value = describe(result)
        return result
    }

    companion object {
        fun isSensitive(extras: PersistableBundle?): Boolean =
            extras?.getBoolean(ClipDescription.EXTRA_IS_SENSITIVE, false) == true

        fun describe(result: Result): String = when (result) {
            Result.SENT -> "Sent to your Mac’s clipboard."
            Result.DISABLED -> "Turn on clipboard sharing in M’AND first."
            Result.NOT_CONNECTED -> "Your Mac isn’t connected."
            Result.EMPTY -> "The clipboard has no text."
            Result.SENSITIVE -> "Not sent: the copied text is marked as sensitive."
            Result.TOO_LARGE -> "Not sent: the text is too large (over 256 KB)."
        }
    }
}
