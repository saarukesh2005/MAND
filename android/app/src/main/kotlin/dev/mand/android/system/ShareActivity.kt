package dev.mand.android.system

import android.content.ContentResolver
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
import dev.mand.core.LinkRules
import dev.mand.android.net.LinkState
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

/**
 * Target of Android's Share sheet (“Share → M’AND”). Files are copied into M’AND while Android
 * still lets us read them, then sent to the Mac; shared text goes to the Mac’s clipboard.
 */
class ShareActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val app = application as MandApp
        // Only content:// URIs: a file:// URI from another app could point at M’AND's own private files.
        val uris = sharedUris(intent).filter { it.scheme == ContentResolver.SCHEME_CONTENT }
        val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
        BridgeService.start(this)

        if (uris.isEmpty()) {
            lifecycleScope.launch {
                app.settings.awaitLoaded()
                // A share may arrive before the link is up; give it a few seconds to connect.
                withTimeoutOrNull(CONNECT_WAIT_MS) { app.client.state.first { it is LinkState.Connected } }
                // A shared web page opens on the Mac; any other text goes to the Mac's clipboard.
                val link = LinkRules.extract(text)
                if (link != null && app.links.send(link, intent.getStringExtra(Intent.EXTRA_SUBJECT))) {
                    Toast.makeText(this@ShareActivity, "Opening on your Mac", Toast.LENGTH_SHORT).show()
                } else {
                    val result = app.clipboard.sendText(text)
                    Toast.makeText(this@ShareActivity, ClipboardBridge.describe(result), Toast.LENGTH_SHORT).show()
                }
                finish()
            }
            return
        }
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

    private companion object {
        const val CONNECT_WAIT_MS = 8_000L
    }

    private fun sharedUris(intent: Intent): List<Uri> = when (intent.action) {
        Intent.ACTION_SEND -> listOfNotNull(intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java))
        Intent.ACTION_SEND_MULTIPLE -> intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java).orEmpty()
        else -> emptyList()
    }
}
