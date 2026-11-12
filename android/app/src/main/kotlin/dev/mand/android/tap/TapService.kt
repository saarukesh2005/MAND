package dev.mand.android.tap

import android.accessibilityservice.AccessibilityService
import android.app.KeyguardManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.PixelFormat
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.SystemClock
import android.view.Choreographer
import android.view.Display
import android.view.View
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.widget.Toast
import dev.mand.android.MandApp
import dev.mand.core.Feature
import dev.mand.core.Message
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors

/**
 * Tap to Send on the phone (adapted from TapDrop's idea, MIT). An Accessibility service — switched on by the user
 * in Settings — so it can (1) capture the screen, (2) light the whole screen white/black over any app for the Mac's
 * notch sensor, and (3) notice the phone being placed against something (proximity "knock").
 * It doesn't read other apps' content (no window-content access) and only watches which app is in front.
 */
class TapService : AccessibilityService(), SensorEventListener {
    private val app get() = application as MandApp
    private val main = Handler(Looper.getMainLooper())
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val executor = Executors.newSingleThreadExecutor()
    private var overlay: View? = null
    private var round: Long = 0
    private var capture: File? = null
    private var foreground: String? = null
    private var lastFarAt = 0L
    private var near = false
    private var lastKnockAt = 0L
    private val timeout = Runnable { finish(sent = false, why = "timeout") }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        val sensors = getSystemService(SensorManager::class.java)
        sensors.getDefaultSensor(Sensor.TYPE_PROXIMITY)?.let { sensors.registerListener(this, it, SensorManager.SENSOR_DELAY_UI) }
        lastFarAt = SystemClock.elapsedRealtime()
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        getSystemService(SensorManager::class.java).unregisterListener(this)
        removeOverlay()
        super.onDestroy()
    }

    override fun onInterrupt() = Unit

    /** Only window changes are subscribed to: we learn which app is in front, nothing else. */
    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        if (event.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val pkg = event.packageName?.toString() ?: return
        if (pkg != packageName && pkg != "com.android.systemui") foreground = pkg
    }

    // ---- Knock: the proximity sensor goes near after being far for a moment ----

    override fun onSensorChanged(event: SensorEvent) {
        val nowNear = event.values[0] < minOf(5f, event.sensor.maximumRange)
        val now = SystemClock.elapsedRealtime()
        if (nowNear && !near && now - lastFarAt >= KNOCK_FAR_MS && now - lastKnockAt >= KNOCK_GAP_MS && canTapNow() == null) {
            lastKnockAt = now
            app.client.sendAsync(Message.TapKnock)
        }
        if (!nowNear) lastFarAt = if (near) now else lastFarAt
        near = nowNear
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit

    /** Null when a tap may run now, otherwise why not (sent to the Mac as the decline reason). */
    private fun canTapNow(): String? {
        if (!app.client.macSupports(Feature.TAP)) return "off"
        if (!getSystemService(PowerManager::class.java).isInteractive) return "screen-off"
        if (getSystemService(KeyguardManager::class.java).isKeyguardLocked) return "locked"
        if (foreground in app.settings.prefs.value.tapPausedApps) return "paused-app"
        if (overlay != null) return "busy"
        return null
    }

    // ---- A light-key round ----

    fun onGrab(id: Long) = main.post {
        canTapNow()?.let { why ->
            app.client.sendAsync(Message.TapDecline(id, why))
            if (why == "paused-app") toast("Tap to Send is paused in this app")
            return@post
        }
        round = id
        // Capture first (before the white screen covers it), then light up.
        takeScreenshot(Display.DEFAULT_DISPLAY, executor, object : TakeScreenshotCallback {
            override fun onSuccess(result: ScreenshotResult) {
                val file = runCatching { save(result) }.getOrNull()
                main.post {
                    if (round != id) return@post
                    if (file == null) {
                        app.client.sendAsync(Message.TapDecline(id, "capture-failed"))
                        return@post
                    }
                    capture = file
                    showOverlay(Color.WHITE) { app.client.sendAsync(Message.TapLight(id, on = true)) }
                    main.postDelayed(timeout, ROUND_TIMEOUT_MS)
                }
            }

            override fun onFailure(errorCode: Int) {
                // Secure screens (passwords, banking, DRM video) can't be captured: decline, nothing lights up.
                main.post { if (round == id) app.client.sendAsync(Message.TapDecline(id, "secure-screen")) }
            }
        })
    }

    fun onSeen(id: Long) = main.post {
        if (id != round || overlay == null) return@post
        showOverlay(Color.BLACK) { app.client.sendAsync(Message.TapLight(id, on = false)) }
    }

    fun onResult(id: Long, ok: Boolean, why: String?) = main.post {
        if (id != round) return@post
        finish(sent = ok, why = why)
    }

    private fun finish(sent: Boolean, why: String?) {
        main.removeCallbacks(timeout)
        removeOverlay()
        val file = capture
        capture = null
        round = 0
        if (sent && file != null) {
            scope.launch { app.files.sendOwnFile(file, file.name) }
            toast("Sending to your Mac")
        } else {
            file?.delete()
            if (why != null && why != "other-phone") toast(explain(why))
        }
    }

    // ---- Overlay: full screen, over the status bar, at full brightness ----

    private fun showOverlay(color: Int, onDrawn: () -> Unit) {
        val wm = getSystemService(WindowManager::class.java)
        val view = overlay ?: View(this).also { v ->
            val lp = WindowManager.LayoutParams(
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.MATCH_PARENT,
                WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                    WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS or WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON,
                PixelFormat.OPAQUE,
            ).apply {
                screenBrightness = 1f
                layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
            }
            wm.addView(v, lp)
            overlay = v
        }
        view.setBackgroundColor(color)
        // Report only once the frame is actually on the display (two frames later, to be safe).
        Choreographer.getInstance().postFrameCallback {
            Choreographer.getInstance().postFrameCallback { onDrawn() }
        }
    }

    private fun removeOverlay() {
        overlay?.let { runCatching { getSystemService(WindowManager::class.java).removeView(it) } }
        overlay = null
    }

    private fun save(result: ScreenshotResult): File {
        val hardware = Bitmap.wrapHardwareBuffer(result.hardwareBuffer, result.colorSpace)
            ?: error("no bitmap")
        val bitmap = hardware.copy(Bitmap.Config.ARGB_8888, false)
        result.hardwareBuffer.close()
        val name = "Tap " + SimpleDateFormat("yyyy-MM-dd HH.mm.ss", Locale.US).format(Date()) + ".png"
        val file = File(File(cacheDir, "tap").apply { mkdirs() }, name)
        file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        bitmap.recycle()
        return file
    }

    private fun toast(text: String) = main.post { Toast.makeText(this, text, Toast.LENGTH_SHORT).show() }

    companion object {
        private const val KNOCK_FAR_MS = 500L
        private const val KNOCK_GAP_MS = 1_500L
        private const val ROUND_TIMEOUT_MS = 6_000L

        @Volatile var instance: TapService? = null
            private set

        fun explain(why: String): String = when (why) {
            "not-seen" -> "Your Mac didn’t see the screen light. Hold the top of the phone right on the notch."
            "stayed-lit" -> "Your Mac couldn’t confirm it was this phone. Hold it flat against the notch."
            "no-light-sent", "no-key-off", "timeout" -> "Tap didn’t finish in time. Try again."
            "phone-left" -> "The phone moved away too soon."
            else -> "Tap didn’t send ($why)."
        }

        fun isEnabled(context: Context): Boolean {
            val enabled = android.provider.Settings.Secure.getString(
                context.contentResolver, android.provider.Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
            ) ?: return false
            val me = android.content.ComponentName(context, TapService::class.java).flattenToString()
            return enabled.split(':').any { it.equals(me, ignoreCase = true) }
        }
    }
}

/** Routes the Mac's tap.* messages to the service (declines when it isn't switched on). */
class TapBridge(private val app: MandApp) : dev.mand.android.net.FeatureHandler {
    override fun onMessage(message: Message) {
        val service = TapService.instance
        when (message) {
            is Message.TapGrab -> service?.onGrab(message.round)
                ?: app.client.sendAsync(Message.TapDecline(message.round, "off"))
            is Message.TapSeen -> service?.onSeen(message.round)
            is Message.TapResult -> service?.onResult(message.round, message.ok, message.why)
            else -> Unit
        }
    }
}
