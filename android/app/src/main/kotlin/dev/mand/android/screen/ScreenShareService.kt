package dev.mand.android.screen

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Bundle
import android.os.IBinder
import android.util.Log
import android.view.WindowManager
import dev.mand.android.MandApp
import dev.mand.android.R
import dev.mand.core.Feature
import dev.mand.core.Message
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * Built-in screen mirroring (`screen.v1`): records the screen with MediaProjection (after the person
 * tapped Start now), encodes H.264 and streams it to the Mac. Frames are dropped, never queued, when
 * the network is slower than the screen, so the picture on the Mac never lags behind.
 */
class ScreenShareService : Service() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var projection: MediaProjection? = null
    private var display: VirtualDisplay? = null
    private var codec: MediaCodec? = null
    private var drain: Thread? = null
    private val running = AtomicBoolean(false)
    private val sending = AtomicBoolean(false)
    private val app get() = application as MandApp

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSharing(if (intent.getBooleanExtra(EXTRA_FROM_MAC, false)) "mac" else "phone")
            return START_NOT_STICKY
        }
        val code = intent?.getIntExtra(EXTRA_CODE, 0) ?: 0
        val data = intent?.getParcelableExtra(EXTRA_DATA, Intent::class.java)
        // Android requires the foreground notification before the projection is created.
        startForeground(NOTIFICATION_ID, notification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
        if (data == null || running.get()) return START_NOT_STICKY
        runCatching { begin(code, data) }.onFailure {
            Log.w(TAG, "Couldn't start screen sharing", it)
            stopSharing("failed")
        }
        return START_NOT_STICKY
    }

    private fun begin(code: Int, data: Intent) {
        val manager = getSystemService(MediaProjectionManager::class.java)
        val projection = manager.getMediaProjection(code, data) ?: error("no projection")
        this.projection = projection
        projection.registerCallback(object : MediaProjection.Callback() {
            override fun onStop() = stopSharing("phone")
        }, null)

        val bounds = getSystemService(WindowManager::class.java).currentWindowMetrics.bounds
        val (width, height) = encodeSize(bounds.width(), bounds.height())
        val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, width, height).apply {
            setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
            setInteger(MediaFormat.KEY_BIT_RATE, BIT_RATE)
            setInteger(MediaFormat.KEY_FRAME_RATE, FRAME_RATE)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
            // Keep sending (repeated) frames while the screen is still, so the Mac always has a picture.
            setLong(MediaFormat.KEY_REPEAT_PREVIOUS_FRAME_AFTER, 100_000L)
        }
        val codec = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
        codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        val surface = codec.createInputSurface()
        codec.start()
        this.codec = codec
        running.set(true)
        app.client.sendAsync(Message.ScreenStart(width, height))
        display = projection.createVirtualDisplay(
            "M’AND", width, height, resources.displayMetrics.densityDpi,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR, surface, null, null,
        )
        drain = Thread({ drainLoop(codec) }, "mand-screen").apply { start() }
    }

    /** Reads encoded frames and sends them, dropping frames (and asking for a fresh key frame) when busy. */
    private fun drainLoop(codec: MediaCodec) {
        val info = MediaCodec.BufferInfo()
        var config = ByteArray(0)
        var seq = 0L
        var needKey = true
        while (running.get()) {
            val index = try { codec.dequeueOutputBuffer(info, 20_000) } catch (e: IllegalStateException) { break }
            if (index < 0) continue
            val buffer = codec.getOutputBuffer(index)
            val bytes = ByteArray(info.size)
            buffer?.position(info.offset)
            buffer?.get(bytes, 0, info.size)
            codec.releaseOutputBuffer(index, false)
            if (info.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0) {
                config = bytes
                continue
            }
            val key = info.flags and MediaCodec.BUFFER_FLAG_KEY_FRAME != 0
            if (needKey && !key) continue
            val payload = if (key) config + bytes else bytes
            if (payload.isEmpty() || payload.size > Message.MAX_SCREEN_FRAME_BYTES || !sending.compareAndSet(false, true)) {
                needKey = true
                requestKeyFrame(codec)
                continue
            }
            needKey = false
            val message = Message.ScreenFrame(seq++, key, payload)
            scope.launch {
                try {
                    if (!app.client.macSupports(Feature.SCREEN) || !app.client.send(message)) stopSharing("disconnected")
                } finally {
                    sending.set(false)
                }
            }
        }
    }

    private fun requestKeyFrame(codec: MediaCodec) {
        runCatching { codec.setParameters(Bundle().apply { putInt(MediaCodec.PARAMETER_KEY_REQUEST_SYNC_FRAME, 0) }) }
    }

    @Synchronized
    private fun stopSharing(reason: String) {
        val wasRunning = running.getAndSet(false)
        display?.release(); display = null
        runCatching { codec?.signalEndOfInputStream() }
        drain?.join(500); drain = null
        runCatching { codec?.stop() }; codec?.release(); codec = null
        projection?.let { p -> projection = null; runCatching { p.stop() } }
        if (wasRunning && reason != "mac" && app.client.macSupports(Feature.SCREEN)) {
            app.client.sendAsync(Message.ScreenStop(reason))
        }
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        if (running.get()) stopSharing("phone")
        scope.cancel()
        super.onDestroy()
    }

    private fun notification(): Notification {
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, getString(R.string.channel_screen), NotificationManager.IMPORTANCE_LOW),
        )
        val stop = PendingIntent.getService(
            this, 0, Intent(this, ScreenShareService::class.java).setAction(ACTION_STOP), PendingIntent.FLAG_IMMUTABLE,
        )
        return Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(getString(R.string.screen_sharing_title))
            .setContentText(getString(R.string.screen_sharing_text))
            .setOngoing(true)
            .addAction(Notification.Action.Builder(null, getString(R.string.screen_stop), stop).build())
            .build()
    }

    companion object {
        private const val TAG = "MandScreen"
        private const val CHANNEL_ID = "mand_screen"
        private const val NOTIFICATION_ID = 4201
        private const val EXTRA_CODE = "code"
        private const val EXTRA_DATA = "data"
        private const val ACTION_STOP = "dev.mand.android.screen.STOP"
        private const val EXTRA_FROM_MAC = "fromMac"
        private const val MAX_SIDE = 1280
        private const val BIT_RATE = 4_000_000
        private const val FRAME_RATE = 30

        fun start(context: Context, code: Int, data: Intent) {
            context.startForegroundService(
                Intent(context, ScreenShareService::class.java).putExtra(EXTRA_CODE, code).putExtra(EXTRA_DATA, data),
            )
        }

        /** The Mac asked to stop. */
        fun stop(context: Context) {
            // Only reaches a running service; starting a stopped one from the background isn't allowed (or needed).
            runCatching {
                context.startService(Intent(context, ScreenShareService::class.java).setAction(ACTION_STOP).putExtra(EXTRA_FROM_MAC, true))
            }
        }

        /** Scales so the long side is at most [MAX_SIDE], keeping both sides even (encoders need it). */
        internal fun encodeSize(width: Int, height: Int): Pair<Int, Int> {
            val scale = minOf(1.0, MAX_SIDE.toDouble() / max(width, height))
            fun even(v: Double) = max(16, (v.roundToInt() / 2) * 2)
            return even(width * scale) to even(height * scale)
        }
    }
}
