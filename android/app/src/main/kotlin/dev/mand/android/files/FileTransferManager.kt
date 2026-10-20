package dev.mand.android.files

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Environment
import android.provider.MediaStore
import android.provider.OpenableColumns
import android.util.Log
import android.webkit.MimeTypeMap
import dev.mand.android.net.BridgeClient
import dev.mand.android.net.FeatureHandler
import dev.mand.core.Feature
import dev.mand.core.Message
import dev.mand.core.SafeFileName
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileInputStream
import java.io.RandomAccessFile
import java.security.MessageDigest
import java.util.UUID

sealed interface TransferState {
    data object Preparing : TransferState
    data object Waiting : TransferState
    data object Offered : TransferState
    data object Active : TransferState
    data object Interrupted : TransferState
    data object Done : TransferState
    data object AlreadyThere : TransferState
    data class Failed(val reason: String) : TransferState
    data object Cancelled : TransferState
}

data class TransferItem(
    val id: String,
    val name: String,
    val incoming: Boolean,
    val size: Long,
    val transferred: Long = 0,
    val bytesPerSecond: Double = 0.0,
    val state: TransferState,
) {
    val isFinished: Boolean
        get() = state is TransferState.Done || state is TransferState.AlreadyThere ||
            state is TransferState.Failed || state is TransferState.Cancelled
}

/**
 * Phone side of `file.v1` (protocol §3a). Mirrors mac/Sources/MandMacKit/Files/FileTransferService.swift.
 * All state is touched only on [worker] (one thread), so no locks are needed.
 * Received files land in Downloads/M’AND via MediaStore (no storage permission needed).
 */
class FileTransferManager(private val context: Context, private val client: BridgeClient) : FeatureHandler {
    @OptIn(ExperimentalCoroutinesApi::class)
    private val worker = Dispatchers.IO.limitedParallelism(1)
    private val scope = CoroutineScope(SupervisorJob() + worker)

    private val _items = MutableStateFlow<List<TransferItem>>(emptyList())
    val items: StateFlow<List<TransferItem>> = _items.asStateFlow()

    private val incoming = mutableMapOf<String, Incoming>()
    private val outgoing = linkedMapOf<String, Outgoing>()
    private var connected = false

    private val partialDir get() = File(context.filesDir, "partial").apply { mkdirs() }
    private val outboxDir get() = File(context.cacheDir, "outbox").apply { mkdirs() }

    // ---- FeatureHandler ----

    override fun onConnected(macFeatures: Set<String>) {
        scope.launch {
            connected = Feature.FILES in macFeatures
            if (connected) {
                outgoing.values.forEach { t -> update(t.tid) { if (it.state == TransferState.Interrupted) it.copy(state = TransferState.Waiting) else it } }
                pump()
            }
        }
    }

    override fun onDisconnected() {
        scope.launch {
            connected = false
            incoming.values.forEach { t ->
                runCatching { t.file.close() }
                update(t.offer.tid) { it.copy(state = TransferState.Interrupted, bytesPerSecond = 0.0) }
            }
            incoming.clear() // partial files are kept for resuming
            outgoing.values.forEach { t ->
                runCatching { t.input?.close() }
                t.input = null
                t.doneSent = false
                update(t.tid) {
                    if (it.state == TransferState.Offered || it.state == TransferState.Active) {
                        it.copy(state = TransferState.Interrupted, bytesPerSecond = 0.0)
                    } else {
                        it
                    }
                }
            }
        }
    }

    override fun onMessage(message: Message) {
        scope.launch {
            when (message) {
                is Message.FileOffer -> receiveOffer(message)
                is Message.FileChunk -> receiveChunk(message)
                is Message.FileDone -> receiveDone(message.tid)
                is Message.FileAccept -> accepted(message.tid, message.offset)
                is Message.FileReject -> rejected(message.tid, message.reason)
                is Message.FileAck -> acked(message.tid, message.received)
                is Message.FileResult -> result(message.tid, message.ok, message.reason)
                is Message.FileCancel -> peerCancelled(message.tid)
                else -> Unit
            }
        }
    }

    // ---- Public API ----

    /**
     * Copies the shared/picked files into app storage (while this app still has permission to read
     * them), then queues them for sending. Call from the Activity that received the URIs.
     */
    suspend fun importAndSend(uris: List<Uri>): Int = withContext(Dispatchers.IO) {
        var count = 0
        for (uri in uris) {
            val name = displayName(uri) ?: "file"
            val id = UUID.randomUUID().toString()
            val safe = runCatching { SafeFileName.components(name).last() }.getOrDefault("file")
            val target = File(File(outboxDir, id).apply { mkdirs() }, safe)
            val copied = runCatching {
                context.contentResolver.openInputStream(uri)?.use { input ->
                    target.outputStream().use { input.copyTo(it, BUFFER) }
                } != null
            }.getOrDefault(false)
            if (!copied) {
                target.parentFile?.deleteRecursively()
                continue
            }
            withContext(worker) { enqueue(id, target, safe) }
            count++
        }
        count
    }

    fun cancel(id: String) {
        scope.launch {
            outgoing.remove(id)?.let { t ->
                runCatching { t.input?.close() }
                client.send(Message.FileCancel(id, "user"))
                update(id) { it.copy(state = TransferState.Cancelled) }
                t.source.parentFile?.deleteRecursively()
                pump()
            }
            incoming.remove(id)?.let { t ->
                runCatching { t.file.close() }
                t.partFile.delete()
                client.send(Message.FileCancel(id, "user"))
                update(id) { it.copy(state = TransferState.Cancelled) }
            }
        }
    }

    fun clearFinished() {
        scope.launch { _items.update { list -> list.filterNot { it.isFinished } } }
    }

    // ---- Incoming (Mac → phone) ----

    private class Incoming(
        val offer: Message.FileOffer,
        val components: List<String>,
        val partFile: File,
        val file: RandomAccessFile,
        val digest: MessageDigest,
        var received: Long,
    ) {
        val meter = SpeedMeter(received)
    }

    private suspend fun receiveOffer(offer: Message.FileOffer) {
        if (incoming.containsKey(offer.tid)) return
        if (incoming.size >= MAX_CONCURRENT_INCOMING) return reject(offer.tid, "busy")
        val components = runCatching { SafeFileName.components(offer.name) }.getOrNull()
            ?: return reject(offer.tid, "invalid_name")
        val relative = relativePath(components)
        val name = components.last()

        if (existingMatches(relative, name, offer.size, offer.sha256)) {
            client.send(Message.FileReject(offer.tid, "already_exists"))
            add(TransferItem(offer.tid, components.joinToString("/"), true, offer.size, offer.size, 0.0, TransferState.AlreadyThere))
            return
        }

        val partFile = File(partialDir, "${offer.sha256}-${offer.size}.part")
        if (partFile.length() > offer.size) partFile.delete()
        if (context.filesDir.usableSpace - FREE_SPACE_MARGIN < (offer.size - partFile.length()) * 2) {
            return reject(offer.tid, "no_space") // partial + copy into Downloads
        }
        val digest = MessageDigest.getInstance("SHA-256")
        var already = 0L
        if (partFile.exists()) {
            FileInputStream(partFile).use { input ->
                val buffer = ByteArray(BUFFER)
                while (true) {
                    val n = input.read(buffer)
                    if (n < 0) break
                    digest.update(buffer, 0, n)
                    already += n
                }
            }
        }
        val file = RandomAccessFile(partFile, "rw").apply {
            setLength(already)
            seek(already)
        }
        incoming[offer.tid] = Incoming(offer, components, partFile, file, digest, already)
        val display = components.joinToString("/")
        _items.update { list ->
            list.filterNot { it.incoming && it.name == display && it.state == TransferState.Interrupted } +
                TransferItem(offer.tid, display, true, offer.size, already, 0.0, TransferState.Active)
        }
        client.send(Message.FileAccept(offer.tid, already))
        if (offer.size == 0L) receiveDone(offer.tid)
    }

    private suspend fun reject(tid: String, reason: String) {
        client.send(Message.FileReject(tid, reason))
    }

    private suspend fun receiveChunk(chunk: Message.FileChunk) {
        val t = incoming[chunk.tid] ?: return
        if (chunk.offset != t.received || t.received + chunk.data.size > t.offer.size) {
            return failIncoming(chunk.tid, "out_of_order")
        }
        try {
            t.file.write(chunk.data)
        } catch (e: java.io.IOException) {
            return failIncoming(chunk.tid, "no_space")
        }
        t.digest.update(chunk.data)
        t.received += chunk.data.size
        val speed = t.meter.record(t.received)
        client.send(Message.FileAck(chunk.tid, t.received))
        update(chunk.tid) { it.copy(transferred = t.received, bytesPerSecond = speed) }
    }

    private suspend fun receiveDone(tid: String) {
        val t = incoming.remove(tid) ?: return
        runCatching { t.file.close() }
        val hex = t.digest.digest().toHex()
        if (t.received != t.offer.size || hex != t.offer.sha256) {
            t.partFile.delete()
            client.send(Message.FileResult(tid, false, "integrity"))
            update(tid) { it.copy(state = TransferState.Failed("The file was damaged in transit and was not saved.")) }
            return
        }
        val saved = runCatching { publishToDownloads(t.partFile, relativePath(t.components), t.components.last()) }
        t.partFile.delete()
        if (saved.isSuccess) {
            client.send(Message.FileResult(tid, true, null))
            update(tid) { it.copy(state = TransferState.Done, transferred = t.offer.size, bytesPerSecond = 0.0) }
        } else {
            Log.w(TAG, "Saving a received file failed: ${saved.exceptionOrNull()?.javaClass?.simpleName}")
            client.send(Message.FileResult(tid, false, "no_space"))
            update(tid) { it.copy(state = TransferState.Failed("Couldn’t save the file to Downloads.")) }
        }
    }

    private suspend fun failIncoming(tid: String, reason: String) {
        val t = incoming.remove(tid) ?: return
        runCatching { t.file.close() }
        t.partFile.delete()
        client.send(Message.FileCancel(tid, reason))
        update(tid) { it.copy(state = TransferState.Failed("Transfer stopped ($reason).")) }
    }

    private suspend fun peerCancelled(tid: String) {
        incoming.remove(tid)?.let { t ->
            runCatching { t.file.close() }
            t.partFile.delete()
            update(tid) { it.copy(state = TransferState.Cancelled) }
        }
        outgoing.remove(tid)?.let { t ->
            runCatching { t.input?.close() }
            update(tid) { it.copy(state = TransferState.Cancelled) }
            pump()
        }
    }

    /** Copies a verified file into Downloads/M’AND/…; MediaStore adds " (1)" instead of overwriting. */
    private fun publishToDownloads(source: File, relativePath: String, name: String) {
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType(name))
            put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
            ?: throw java.io.IOException("MediaStore insert failed")
        try {
            resolver.openOutputStream(uri)?.use { out -> source.inputStream().use { it.copyTo(out, BUFFER) } }
                ?: throw java.io.IOException("Couldn't open output")
            resolver.update(uri, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null)
        } catch (e: Exception) {
            resolver.delete(uri, null, null)
            throw e
        }
    }

    /** True if Downloads/M’AND already holds a file with this name, size and content. */
    private fun existingMatches(relativePath: String, name: String, size: Long, sha256: String): Boolean {
        val resolver = context.contentResolver
        val projection = arrayOf(MediaStore.MediaColumns._ID)
        val selection = "${MediaStore.MediaColumns.RELATIVE_PATH}=? AND ${MediaStore.MediaColumns.DISPLAY_NAME}=? AND " +
            "${MediaStore.MediaColumns.SIZE}=?"
        val args = arrayOf(relativePath, name, size.toString())
        resolver.query(MediaStore.Downloads.EXTERNAL_CONTENT_URI, projection, selection, args, null)?.use { cursor ->
            while (cursor.moveToNext()) {
                val uri = android.content.ContentUris.withAppendedId(MediaStore.Downloads.EXTERNAL_CONTENT_URI, cursor.getLong(0))
                val hex = runCatching { resolver.openInputStream(uri)?.use { sha256Hex(it) } }.getOrNull()
                if (hex == sha256) return true
            }
        }
        return false
    }

    // ---- Outgoing (phone → Mac) ----

    private class Outgoing(val tid: String, val source: File, val name: String) {
        var size = source.length()
        var sha256 = ""
        var input: java.io.InputStream? = null
        var sent = 0L
        var acked = 0L
        var doneSent = false
        var sending = false
        var meter = SpeedMeter(0)
    }

    private suspend fun enqueue(id: String, file: File, name: String) {
        val t = Outgoing(id, file, name)
        outgoing[id] = t
        add(TransferItem(id, name, false, t.size, state = TransferState.Preparing))
        t.sha256 = withContext(Dispatchers.IO) { file.inputStream().use { sha256Hex(it) } }
        if (t.size > Message.MAX_FILE_SIZE) {
            outgoing.remove(id)
            update(id) { it.copy(state = TransferState.Failed("This file is too large.")) }
            return
        }
        update(id) { it.copy(state = TransferState.Waiting) }
        pump()
    }

    private suspend fun pump() {
        if (!connected) return
        val busy = outgoing.values.any { t ->
            _items.value.firstOrNull { it.id == t.tid }?.state.let { it == TransferState.Offered || it == TransferState.Active }
        }
        if (busy) return
        val next = outgoing.values.firstOrNull { t -> _items.value.firstOrNull { it.id == t.tid }?.state == TransferState.Waiting }
            ?: return
        update(next.tid) { it.copy(state = TransferState.Offered) }
        client.send(Message.FileOffer(next.tid, next.name, next.size, next.sha256))
    }

    private suspend fun accepted(tid: String, offset: Long) {
        val t = outgoing[tid] ?: return
        if (offset < 0 || offset > t.size) return
        val input = runCatching { FileInputStream(t.source) }.getOrNull() ?: run {
            outgoing.remove(tid)
            client.send(Message.FileCancel(tid, "unreadable"))
            update(tid) { it.copy(state = TransferState.Failed("Couldn’t read this file.")) }
            return pump()
        }
        input.channel.position(offset)
        t.input = input
        t.sent = offset
        t.acked = offset
        t.meter = SpeedMeter(offset)
        update(tid) { it.copy(state = TransferState.Active, transferred = offset) }
        sendMore(t)
    }

    private suspend fun sendMore(t: Outgoing) {
        if (t.sending) return // another call is already filling the window
        t.sending = true
        try {
            val input = t.input ?: return
            val buffer = ByteArray(Message.MAX_FILE_CHUNK_BYTES)
            while (connected && t.sent < t.size && t.sent - t.acked < WINDOW_CHUNKS * Message.MAX_FILE_CHUNK_BYTES) {
                val want = minOf(buffer.size.toLong(), t.size - t.sent).toInt()
                val n = input.readNBytes(buffer, 0, want)
                if (n <= 0) {
                    outgoing.remove(t.tid)
                    client.send(Message.FileCancel(t.tid, "unreadable"))
                    update(t.tid) { it.copy(state = TransferState.Failed("The file couldn’t be read while sending.")) }
                    return pump()
                }
                if (!client.send(Message.FileChunk(t.tid, t.sent, buffer.copyOf(n)))) return
                t.sent += n
            }
            if (t.sent == t.size && !t.doneSent) {
                t.doneSent = true
                client.send(Message.FileDone(t.tid))
            }
        } finally {
            t.sending = false
        }
    }

    private suspend fun acked(tid: String, received: Long) {
        val t = outgoing[tid] ?: return
        if (received < t.acked || received > t.sent) return
        t.acked = received
        val speed = t.meter.record(received)
        update(tid) { it.copy(transferred = received, bytesPerSecond = speed) }
        sendMore(t)
    }

    private suspend fun rejected(tid: String, reason: String) {
        val t = outgoing.remove(tid) ?: return
        runCatching { t.input?.close() }
        val state = if (reason == "already_exists") TransferState.AlreadyThere else TransferState.Failed(describeReject(reason))
        update(tid) { it.copy(state = state) }
        if (reason == "already_exists") t.source.parentFile?.deleteRecursively()
        pump()
    }

    private suspend fun result(tid: String, ok: Boolean, reason: String?) {
        val t = outgoing.remove(tid) ?: return
        runCatching { t.input?.close() }
        if (ok) {
            t.source.parentFile?.deleteRecursively()
            update(tid) { it.copy(state = TransferState.Done, transferred = it.size, bytesPerSecond = 0.0) }
        } else {
            val message = if (reason == "integrity") "The Mac found the file damaged in transit. Try again."
            else "The Mac couldn’t save the file (${reason ?: "error"})."
            update(tid) { it.copy(state = TransferState.Failed(message)) }
            t.source.parentFile?.deleteRecursively()
        }
        pump()
    }

    // ---- Helpers ----

    private fun add(item: TransferItem) {
        _items.update { (it + item).takeLast(MAX_ITEMS) }
    }

    private fun update(id: String, change: (TransferItem) -> TransferItem) {
        _items.update { list -> list.map { if (it.id == id) change(it) else it } }
    }

    private fun displayName(uri: Uri): String? =
        context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) cursor.getString(0) else null
        } ?: uri.lastPathSegment

    companion object {
        private const val TAG = "MandFiles"
        private const val BUFFER = 1 shl 20
        private const val WINDOW_CHUNKS = 8L
        private const val MAX_CONCURRENT_INCOMING = 4
        private const val MAX_ITEMS = 200
        private const val FREE_SPACE_MARGIN = 200L * 1024 * 1024
        const val DOWNLOAD_FOLDER = "M’AND"

        internal fun relativePath(components: List<String>): String =
            (listOf(Environment.DIRECTORY_DOWNLOADS, DOWNLOAD_FOLDER) + components.dropLast(1)).joinToString("/") + "/"

        internal fun mimeType(name: String): String =
            MimeTypeMap.getSingleton().getMimeTypeFromExtension(name.substringAfterLast('.', "").lowercase())
                ?: "application/octet-stream"

        fun describeReject(reason: String): String = when (reason) {
            "too_large" -> "The file is too large for the Mac."
            "no_space" -> "The Mac doesn’t have enough free space."
            "invalid_name" -> "The Mac refused the file name."
            "busy" -> "The Mac is busy with other transfers. Try again shortly."
            "disabled" -> "File receiving is turned off on the Mac."
            else -> "The Mac declined the file ($reason)."
        }

        internal fun sha256Hex(input: java.io.InputStream): String {
            val digest = MessageDigest.getInstance("SHA-256")
            val buffer = ByteArray(BUFFER)
            while (true) {
                val n = input.read(buffer)
                if (n < 0) break
                digest.update(buffer, 0, n)
            }
            return digest.digest().toHex()
        }

        private fun ByteArray.toHex(): String = joinToString("") { "%02x".format(it) }
    }
}

/** Rolling transfer-speed estimate over roughly the last second. */
internal class SpeedMeter(start: Long) {
    private val samples = ArrayDeque<Pair<Long, Long>>().apply { add(System.nanoTime() to start) }

    fun record(total: Long): Double {
        val now = System.nanoTime()
        samples.addLast(now to total)
        while (samples.size > 2 && now - samples.first().first > 1_500_000_000L) samples.removeFirst()
        val (t0, b0) = samples.first()
        val seconds = (now - t0) / 1e9
        return if (seconds > 0) (total - b0) / seconds else 0.0
    }
}
