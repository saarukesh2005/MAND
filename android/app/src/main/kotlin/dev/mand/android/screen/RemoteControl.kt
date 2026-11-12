package dev.mand.android.screen

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.view.WindowManager
import dev.mand.android.MandApp
import dev.mand.android.net.FeatureHandler
import dev.mand.android.tap.TapService
import dev.mand.core.Feature
import dev.mand.core.Message

/**
 * Control from the Mac (`control.v1`): taps, swipes and Back/Home/Recents, performed through M’AND's
 * Accessibility service. Accepted only while this phone is sharing its screen with the Mac AND the person
 * has switched the Accessibility service on — otherwise every request is ignored.
 */
class RemoteControl(private val app: MandApp) : FeatureHandler {
    /** Tells the Mac whether it may show control buttons (called when screen sharing starts). */
    fun reportAvailability() {
        if (app.client.macSupports(Feature.CONTROL)) {
            app.client.sendAsync(Message.ControlState(available = ScreenShareService.isRunning && TapService.instance != null))
        }
    }

    override fun onMessage(message: Message) {
        val service = TapService.instance ?: return
        if (!ScreenShareService.isRunning) return
        when (message) {
            is Message.ControlTap -> {
                val (x, y) = point(service, message.x, message.y)
                gesture(service, Path().apply { moveTo(x, y) }, TAP_MS)
            }
            is Message.ControlSwipe -> {
                val (x1, y1) = point(service, message.x1, message.y1)
                val (x2, y2) = point(service, message.x2, message.y2)
                gesture(service, Path().apply { moveTo(x1, y1); lineTo(x2, y2) }, message.ms.toLong())
            }
            is Message.ControlKey -> service.performGlobalAction(
                when (message.key) {
                    Message.ControlKey.Key.BACK -> AccessibilityService.GLOBAL_ACTION_BACK
                    Message.ControlKey.Key.HOME -> AccessibilityService.GLOBAL_ACTION_HOME
                    Message.ControlKey.Key.RECENTS -> AccessibilityService.GLOBAL_ACTION_RECENTS
                },
            )
            else -> Unit
        }
    }

    /** Converts the Mac's 0…10,000 fractions into this screen's pixels. */
    private fun point(service: TapService, fx: Int, fy: Int): Pair<Float, Float> {
        val bounds = service.getSystemService(WindowManager::class.java).maximumWindowMetrics.bounds
        val x = fx.coerceIn(0, Message.CONTROL_SCALE) / Message.CONTROL_SCALE.toFloat() * (bounds.width() - 1)
        val y = fy.coerceIn(0, Message.CONTROL_SCALE) / Message.CONTROL_SCALE.toFloat() * (bounds.height() - 1)
        return x to y
    }

    private fun gesture(service: TapService, path: Path, ms: Long) {
        val stroke = GestureDescription.StrokeDescription(path, 0, ms.coerceIn(1, MAX_GESTURE_MS))
        service.dispatchGesture(GestureDescription.Builder().addStroke(stroke).build(), null, null)
    }

    private companion object {
        const val TAP_MS = 60L
        const val MAX_GESTURE_MS = 3_000L
    }
}
