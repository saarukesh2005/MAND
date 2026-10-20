package dev.mand.android.system

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.lifecycle.lifecycleScope
import dev.mand.android.MandApp
import dev.mand.android.clipboard.ClipboardBridge
import dev.mand.android.service.BridgeService
import dev.mand.core.Feature
import kotlinx.coroutines.launch

/**
 * Target of Android's Share sheet (“Share → M’AND”). Files are copied into M’AND while Android
 * still lets us read them, then sent to the Mac; shared text goes to the Mac’s clipboard.
 */
class ShareActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val app = application as MandApp
        val uris = sharedUris(intent)
        val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()

        if (uris.isEmpty()) {
            val result = app.clipboard.sendText(text)
            Toast.makeText(this, ClipboardBridge.describe(result), Toast.LENGTH_SHORT).show()
            finish()
            return
        }
        BridgeService.start(this)
        Toast.makeText(this, "Preparing ${uris.size} file(s) for your Mac…", Toast.LENGTH_SHORT).show()
        lifecycleScope.launch {
            val count = app.files.importAndSend(uris)
            val connected = app.client.macSupports(Feature.FILES)
            val message = when {
                count == 0 -> "Couldn’t read the shared files."
                connected -> "Sending $count file(s) to your Mac."
                else -> "$count file(s) will be sent when your Mac connects."
            }
            Toast.makeText(this@ShareActivity, message, Toast.LENGTH_SHORT).show()
            finish()
        }
    }

    private fun sharedUris(intent: Intent): List<Uri> = when (intent.action) {
        Intent.ACTION_SEND -> listOfNotNull(intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java))
        Intent.ACTION_SEND_MULTIPLE -> intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java).orEmpty()
        else -> emptyList()
    }
}
