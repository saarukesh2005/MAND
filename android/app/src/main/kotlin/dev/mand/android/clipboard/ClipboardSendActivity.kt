package dev.mand.android.clipboard

import android.app.Activity
import android.os.Bundle
import android.widget.Toast
import dev.mand.android.MandApp

/**
 * Invisible screen opened by the Quick Settings tile. Android only lets the focused app read the
 * clipboard, so this briefly takes focus, sends the text, and closes.
 */
class ClipboardSendActivity : Activity() {
    private var handled = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        overrideActivityTransition(OVERRIDE_TRANSITION_OPEN, 0, 0)
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (!hasFocus || handled) return
        handled = true
        val result = (application as MandApp).clipboard.sendCurrentClip()
        Toast.makeText(this, ClipboardBridge.describe(result), Toast.LENGTH_SHORT).show()
        finish()
        overrideActivityTransition(OVERRIDE_TRANSITION_CLOSE, 0, 0)
    }
}
