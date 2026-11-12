package dev.mand.android.screen

import android.app.Activity
import android.media.projection.MediaProjectionManager
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import dev.mand.android.MandApp
import dev.mand.core.Feature
import dev.mand.core.Message

/**
 * Shows Android's own "Start recording or casting?" prompt. Nothing is shared unless the person taps
 * Start now; the result goes straight to [ScreenShareService]. Has no UI of its own.
 */
class ScreenShareActivity : ComponentActivity() {
    private val consent = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        val app = application as MandApp
        if (result.resultCode == Activity.RESULT_OK && result.data != null) {
            ScreenShareService.start(this, result.resultCode, requireNotNull(result.data))
        } else {
            if (app.client.macSupports(Feature.SCREEN)) app.client.sendAsync(Message.ScreenStop("declined"))
            Toast.makeText(this, "Screen not shared", Toast.LENGTH_SHORT).show()
        }
        finish()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val app = application as MandApp
        if (!app.client.macSupports(Feature.SCREEN)) {
            Toast.makeText(this, "Connect to your Mac first", Toast.LENGTH_SHORT).show()
            finish()
            return
        }
        if (savedInstanceState == null) {
            consent.launch(getSystemService(MediaProjectionManager::class.java).createScreenCaptureIntent())
        }
    }
}
