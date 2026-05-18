package com.ziadyounis.down4more.down4more

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import com.yausername.ffmpeg.FFmpeg
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLException
import com.yausername.youtubedl_android.YoutubeDLRequest
import com.yausername.youtubedl_android.YoutubeDLResponse
import com.yausername.youtubedl_android.YoutubeDL.UpdateChannel
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import android.os.Handler
import android.os.Looper
import java.io.File
import java.io.FileInputStream
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger

/**
 * Flutter plugin that bridges the Dart `AndroidYtDlpBackend` to the
 * `youtubedl-android` library at runtime.
 *
 * - One `MethodChannel` exposes synchronous-ish calls: init, getInfo,
 *   getInfoLines (for `--flat-playlist --dump-json`), getInfoSingle (for
 *   `--print %(playlist_title|)s`), startDownload, cancelDownload.
 * - One `EventChannel` streams download progress events keyed by an
 *   opaque downloadId the Dart side generates. Each event is one of:
 *     - `{downloadId, type: "progress", percent, etaSeconds, line}`
 *     - `{downloadId, type: "completed", exitCode, stdout, stderr}`
 *     - `{downloadId, type: "error",     message}`
 *
 * Downloads run on `Dispatchers.IO` in a process-wide `SupervisorJob` so
 * one failing download doesn't tear down the others.
 */
class YtDlpPlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {

    private lateinit var context: Context
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel

    private var eventSink: EventChannel.EventSink? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val downloadJobs = ConcurrentHashMap<String, Job>()

    /**
     * Number of downloads currently in flight. Drives the foreground-service
     * lifecycle: incremented before `startDownload`, decremented in the
     * coroutine's `finally`. When this hits zero we stop the service so
     * Android removes the ongoing notification.
     */
    private val activeDownloads = AtomicInteger(0)

    @Volatile
    private var initialized = false

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL)
        methodChannel.setMethodCallHandler(this)
        eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL)
        eventChannel.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        scope.cancel()
        downloadJobs.clear()
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "init" -> handleInit(result)
            "getInfo" -> handleGetInfo(call, result)
            "getInfoLines" -> handleGetInfoLines(call, result)
            "getInfoSingle" -> handleGetInfoSingle(call, result)
            "startDownload" -> handleStartDownload(call, result)
            "cancelDownload" -> handleCancelDownload(call, result)
            "exportToMediaStore" -> handleExportToMediaStore(call, result)
            "openFile" -> handleOpenFile(call, result)
            "openFolder" -> handleOpenFolder(call, result)
            else -> result.notImplemented()
        }
    }

    // ── init ────────────────────────────────────────────────────────────────

    @Volatile
    private var ytDlpUpdated = false

    private fun ensureInitialized() {
        if (initialized) return
        synchronized(this) {
            if (initialized) return
            YoutubeDL.getInstance().init(context)
            FFmpeg.getInstance().init(context)
            initialized = true
        }
        // Kick off a background yt-dlp update so the newest extractors are
        // available. Runs outside the synchronized block so it doesn't slow
        // down init — the bundled version works for the first operation while
        // the update downloads in the background.
        if (!ytDlpUpdated) {
            scope.launch {
                try {
                    YoutubeDL.getInstance().updateYoutubeDL(context, UpdateChannel.STABLE)
                } catch (_: Throwable) { /* update failed — use bundled version */ }
                ytDlpUpdated = true
            }
        }
    }

    private fun handleInit(result: MethodChannel.Result) {
        scope.launch {
            try {
                ensureInitialized()
                withContext(Dispatchers.Main) { result.success(null) }
            } catch (e: YoutubeDLException) {
                withContext(Dispatchers.Main) {
                    result.error(ERR_INIT, e.message ?: "youtubedl-android init failed", null)
                }
            } catch (t: Throwable) {
                withContext(Dispatchers.Main) {
                    result.error(ERR_INIT, t.message ?: "Unexpected init failure", null)
                }
            }
        }
    }

    // ── getInfo ─────────────────────────────────────────────────────────────
    //
    // We deliberately run yt-dlp with the caller-provided args and return the
    // raw stdout. The Dart side already knows how to parse `--dump-single-json`
    // (via VideoMetadata.fromJson), `--flat-playlist --dump-json` (via
    // PlaylistEntry.fromJson per line), and `--print %(...)s` output. Keeping
    // parsing on the Dart side avoids duplicating it across platforms.

    private fun handleGetInfo(call: MethodCall, result: MethodChannel.Result) {
        val url = call.argument<String>("url")
        val args = call.argument<List<String>>("args") ?: emptyList()
        if (url.isNullOrBlank()) {
            result.error(ERR_ARG, "url is required", null); return
        }
        scope.launch { runYtDlpSync(url, args, result) }
    }

    private fun handleGetInfoLines(call: MethodCall, result: MethodChannel.Result) {
        // Same as getInfo — the Dart side splits stdout on newlines. We keep
        // them as separate method names so call sites read clearly.
        handleGetInfo(call, result)
    }

    private fun handleGetInfoSingle(call: MethodCall, result: MethodChannel.Result) {
        handleGetInfo(call, result)
    }

    private suspend fun runYtDlpSync(
        url: String,
        args: List<String>,
        result: MethodChannel.Result,
    ) {
        try {
            ensureInitialized()
            val request = YoutubeDLRequest(url)
            applyArgs(request, args)
            val response: YoutubeDLResponse = YoutubeDL.getInstance().execute(request)
            withContext(Dispatchers.Main) {
                result.success(
                    mapOf(
                        "exitCode" to response.exitCode,
                        "stdout" to response.out,
                        "stderr" to response.err,
                    ),
                )
            }
        } catch (e: YoutubeDLException) {
            withContext(Dispatchers.Main) {
                result.error(ERR_YTDLP, e.message ?: "yt-dlp failed", null)
            }
        } catch (e: InterruptedException) {
            withContext(Dispatchers.Main) {
                result.error(ERR_CANCELLED, "Interrupted", null)
            }
        } catch (t: Throwable) {
            withContext(Dispatchers.Main) {
                result.error(ERR_UNKNOWN, t.message ?: "Unexpected failure", null)
            }
        }
    }

    // ── download ────────────────────────────────────────────────────────────

    private fun handleStartDownload(call: MethodCall, result: MethodChannel.Result) {
        val downloadId = call.argument<String>("downloadId")
        val url = call.argument<String>("url")
        val args = call.argument<List<String>>("args") ?: emptyList()
        if (downloadId.isNullOrBlank() || url.isNullOrBlank()) {
            result.error(ERR_ARG, "downloadId and url are required", null); return
        }
        if (downloadJobs.containsKey(downloadId)) {
            result.error(ERR_ARG, "duplicate downloadId: $downloadId", null); return
        }

        // Promote the app to the foreground BEFORE the first download starts
        // so Android doesn't get a chance to kill us between the launch call
        // and the coroutine actually running. Subsequent downloads just bump
        // the active count and reuse the same service.
        val activeAfter = activeDownloads.incrementAndGet()
        DownloadForegroundService.start(context, activeAfter)

        val job = scope.launch {
            try {
                ensureInitialized()
                val request = YoutubeDLRequest(url)
                applyArgs(request, args)
                val response = YoutubeDL.getInstance().execute(
                    request,
                    downloadId,
                ) { progress, etaSeconds, line ->
                    emitOnMain(
                        mapOf(
                            "downloadId" to downloadId,
                            "type" to "progress",
                            "percent" to progress.toDouble(),
                            "etaSeconds" to etaSeconds,
                            "line" to line,
                        ),
                    )
                }
                emitOnMain(
                    mapOf(
                        "downloadId" to downloadId,
                        "type" to "completed",
                        "exitCode" to response.exitCode,
                        "stdout" to response.out,
                        "stderr" to response.err,
                    ),
                )
            } catch (e: YoutubeDLException) {
                emitOnMain(
                    mapOf(
                        "downloadId" to downloadId,
                        "type" to "error",
                        "message" to (e.message ?: "yt-dlp failed"),
                    ),
                )
            } catch (e: InterruptedException) {
                emitOnMain(
                    mapOf(
                        "downloadId" to downloadId,
                        "type" to "cancelled",
                    ),
                )
            } catch (t: Throwable) {
                emitOnMain(
                    mapOf(
                        "downloadId" to downloadId,
                        "type" to "error",
                        "message" to (t.message ?: "Unexpected failure"),
                    ),
                )
            } finally {
                downloadJobs.remove(downloadId)
                onDownloadFinished()
            }
        }
        downloadJobs[downloadId] = job
        // Acknowledge immediately so the Dart side can start listening on the
        // EventChannel before the first progress tick lands.
        result.success(null)
    }

    /**
     * Called whenever a download coroutine exits (success, cancel, or error).
     * Decrements [activeDownloads]; if the count reaches zero we stop the
     * foreground service so the ongoing notification clears. If we still
     * have other downloads in flight we re-fire `start` so the notification
     * text reflects the new count.
     */
    private fun onDownloadFinished() {
        val remaining = activeDownloads.updateAndGet { (it - 1).coerceAtLeast(0) }
        if (remaining == 0) {
            DownloadForegroundService.stop(context)
        } else {
            DownloadForegroundService.start(context, remaining)
        }
    }

    private fun handleCancelDownload(call: MethodCall, result: MethodChannel.Result) {
        val downloadId = call.argument<String>("downloadId")
        if (downloadId.isNullOrBlank()) {
            result.error(ERR_ARG, "downloadId is required", null); return
        }
        try {
            YoutubeDL.getInstance().destroyProcessById(downloadId)
        } catch (_: Throwable) {
            // destroyProcessById throws if the id is unknown; we treat that as
            // already-cancelled and emit a synthetic cancelled event so the
            // Dart side's stream still terminates.
        }
        // Cancelling the coroutine triggers its `finally` block which calls
        // onDownloadFinished(); we don't have to bump the counter here.
        downloadJobs[downloadId]?.cancel()
        downloadJobs.remove(downloadId)
        emitOnMain(mapOf("downloadId" to downloadId, "type" to "cancelled"))
        result.success(null)
    }

    // ── MediaStore export ───────────────────────────────────────────────────
    //
    // yt-dlp writes into the app's scoped scratch dir (no permission needed).
    // To make the file user-visible in the gallery / Files app we copy it to
    // `Movies/Down4More[/<subfolder>]` via MediaStore.Video / MediaStore.Audio.
    // On API 29+ MediaStore manages the `RELATIVE_PATH` for us. On API 28 and
    // older the legacy path goes via `Environment.getExternalStoragePublicDirectory`.
    //
    // The returned map gives the Dart side:
    //   - `uri`          : content://media/... (or file://... on legacy)
    //   - `displayPath`  : user-friendly path like /storage/emulated/0/Movies/Down4More/title.mp4

    private fun handleExportToMediaStore(call: MethodCall, result: MethodChannel.Result) {
        val srcPath = call.argument<String>("srcPath")
        val displayName = call.argument<String>("displayName")
        val mimeType = call.argument<String>("mimeType") ?: "video/mp4"
        val subfolder = call.argument<String>("subfolder")
        val isAudio = call.argument<Boolean>("isAudio") ?: false
        // Sidecar files (`.srt`, `.vtt`, ...) need to land in the same folder
        // as the parent video, but MediaStore.Video / MediaStore.Audio reject
        // any non-A/V MIME type — so we route them through MediaStore.Files
        // (API 29+) or write them as plain files without indexing them as
        // media (API ≤28).
        val isSidecar = call.argument<Boolean>("isSidecar") ?: false

        if (srcPath.isNullOrBlank() || displayName.isNullOrBlank()) {
            result.error(ERR_ARG, "srcPath and displayName are required", null); return
        }
        val src = File(srcPath)
        if (!src.exists()) {
            result.error(ERR_EXPORT, "Source file not found: $srcPath", null); return
        }

        scope.launch {
            try {
                val payload = exportToMediaStore(
                    src = src,
                    displayName = displayName,
                    mimeType = mimeType,
                    subfolder = subfolder,
                    isAudio = isAudio,
                    isSidecar = isSidecar,
                )
                withContext(Dispatchers.Main) { result.success(payload) }
            } catch (t: Throwable) {
                withContext(Dispatchers.Main) {
                    result.error(ERR_EXPORT, t.message ?: "MediaStore export failed", null)
                }
            }
        }
    }

    private fun exportToMediaStore(
        src: File,
        displayName: String,
        mimeType: String,
        subfolder: String?,
        isAudio: Boolean,
        isSidecar: Boolean = false,
    ): Map<String, Any?> {
        // Subtitles ride alongside their parent video. We always use the
        // parent's root dir (Movies for video, Music for audio) so the .srt
        // ends up next to the .mp4 / .mp3 the user actually opens.
        val rootDir = if (isAudio) {
            Environment.DIRECTORY_MUSIC
        } else {
            Environment.DIRECTORY_MOVIES
        }
        val relativeFolder = buildString {
            append(rootDir).append('/').append("Down4More")
            if (!subfolder.isNullOrBlank()) {
                append('/').append(sanitizeRelativePath(subfolder))
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // API 29+: MediaStore owns the file; we never touch the public path
            // directly. RELATIVE_PATH must end with a slash for the directory.
            val resolver = context.contentResolver
            val collection = when {
                // MediaStore.Files accepts arbitrary MIME types and honours
                // RELATIVE_PATH the same way as the typed collections, so the
                // .srt lands inside Movies/Down4More/ next to the .mp4 even
                // though it isn't a video itself.
                isSidecar ->
                    MediaStore.Files.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                isAudio ->
                    MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
                else ->
                    MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            }
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, displayName)
                put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                put(MediaStore.MediaColumns.RELATIVE_PATH, "$relativeFolder/")
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val itemUri = resolver.insert(collection, values)
                ?: throw IllegalStateException("MediaStore.insert returned null")
            try {
                resolver.openOutputStream(itemUri, "w")?.use { out ->
                    FileInputStream(src).use { input -> input.copyTo(out) }
                } ?: throw IllegalStateException("openOutputStream returned null")
                val finalize = ContentValues().apply {
                    put(MediaStore.MediaColumns.IS_PENDING, 0)
                }
                resolver.update(itemUri, finalize, null, null)
            } catch (t: Throwable) {
                // Roll back the partially-written MediaStore row so the user
                // doesn't see a phantom 0-byte file in their gallery.
                runCatching { resolver.delete(itemUri, null, null) }
                throw t
            }
            // Best-effort cleanup of the scratch copy. Failure here is
            // cosmetic — the file is already public, the scratch one is just
            // dead bytes.
            runCatching { src.delete() }
            val displayPath = "/storage/emulated/0/$relativeFolder/$displayName"
            return mapOf(
                "uri" to itemUri.toString(),
                "displayPath" to displayPath,
            )
        } else {
            // API ≤ 28: write directly under the public Movies/ folder.
            // WRITE_EXTERNAL_STORAGE permission is declared in the manifest
            // with maxSdkVersion="28" so it applies here.
            @Suppress("DEPRECATION")
            val publicRoot = Environment.getExternalStoragePublicDirectory(rootDir)
            val targetDir = File(publicRoot, buildString {
                append("Down4More")
                if (!subfolder.isNullOrBlank()) {
                    append('/').append(sanitizeRelativePath(subfolder))
                }
            })
            if (!targetDir.exists() && !targetDir.mkdirs()) {
                throw IllegalStateException("Could not create ${targetDir.path}")
            }
            val target = File(targetDir, displayName)
            FileInputStream(src).use { input ->
                target.outputStream().use { output -> input.copyTo(output) }
            }
            runCatching { src.delete() }
            // Index the file under the MediaStore so the gallery picks it up
            // without a reboot. Sidecars (`.srt`, ...) skip this — the typed
            // Audio / Video collections reject non-A/V MIME types and we
            // already wrote the file to disk so the user can see it.
            if (!isSidecar) {
                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DATA, target.absolutePath)
                    put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                    put(MediaStore.MediaColumns.DISPLAY_NAME, displayName)
                }
                val collection = if (isAudio) {
                    @Suppress("DEPRECATION")
                    MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
                } else {
                    @Suppress("DEPRECATION")
                    MediaStore.Video.Media.EXTERNAL_CONTENT_URI
                }
                val uri = runCatching { context.contentResolver.insert(collection, values) }
                    .getOrNull()
                return mapOf(
                    "uri" to (uri?.toString() ?: "file://${target.absolutePath}"),
                    "displayPath" to target.absolutePath,
                )
            }
            return mapOf(
                "uri" to "file://${target.absolutePath}",
                "displayPath" to target.absolutePath,
            )
        }
    }

    private fun sanitizeRelativePath(input: String): String {
        // MediaStore RELATIVE_PATH rejects components with `..` and bare
        // `/`-prefixed strings. Strip those and any control chars but leave
        // user-friendly characters (spaces, dashes) alone.
        return input
            .replace(Regex("""[\u0000-\u001f]"""), "")
            .split('/')
            .map { it.trim().replace("..", "_") }
            .filter { it.isNotEmpty() }
            .joinToString("/")
    }

    // ── open file / folder ──────────────────────────────────────────────────
    //
    // The UI's "Open" / "Folder" buttons need to dispatch ACTION_VIEW intents
    // with content URIs (file:// is blocked since API 24). We accept the
    // user-friendly /storage/emulated/0/Movies/Down4More/... path and resolve
    // back to a MediaStore URI for the receiving app.

    private fun handleOpenFile(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        if (path.isNullOrBlank()) {
            result.error(ERR_ARG, "path is required", null); return
        }
        try {
            val uri = resolveContentUri(path)
            val mime = guessMimeType(path)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, mime)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            context.startActivity(intent)
            result.success(true)
        } catch (t: Throwable) {
            result.success(false)
        }
    }

    private fun handleOpenFolder(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path") ?: ""
        try {
            // We can't deep-link into a folder the way desktop file managers
            // do — Android's storage UI is collection-scoped. The closest
            // analogue is ACTION_VIEW on a directory-style URI which most
            // gallery / Files apps treat as "show the parent collection".
            val parent = if (path.isNotBlank()) {
                File(path).parentFile?.absolutePath ?: path
            } else {
                Environment.getExternalStoragePublicDirectory(
                    Environment.DIRECTORY_MOVIES,
                ).absolutePath + "/Down4More"
            }
            val uri = Uri.parse("content://com.android.externalstorage.documents/document/primary:" +
                parent.removePrefix("/storage/emulated/0/"))
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "vnd.android.document/directory")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            context.startActivity(intent)
            result.success(true)
        } catch (t: Throwable) {
            result.success(false)
        }
    }

    private fun resolveContentUri(path: String): Uri {
        // Files we wrote via exportToMediaStore are indexed under
        // MediaStore.Video / Audio. If MediaStore lookup fails the caller
        // gets a `file://` URI as a last resort — Android may refuse it on
        // API 24+ but it lets older viewers still work.
        val mediaUri = findMediaStoreUri(path)
        if (mediaUri != null) return mediaUri
        return Uri.fromFile(File(path))
    }

    private fun findMediaStoreUri(path: String): Uri? {
        val collections = listOf(
            MediaStore.Video.Media.EXTERNAL_CONTENT_URI to MediaStore.Video.Media._ID,
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI to MediaStore.Audio.Media._ID,
        )
        for ((collection, idColumn) in collections) {
            val cursor = runCatching {
                context.contentResolver.query(
                    collection,
                    arrayOf(idColumn),
                    "${MediaStore.MediaColumns.DATA}=?",
                    arrayOf(path),
                    null,
                )
            }.getOrNull() ?: continue
            cursor.use {
                if (it.moveToFirst()) {
                    val id = it.getLong(0)
                    return Uri.withAppendedPath(collection, id.toString())
                }
            }
        }
        return null
    }

    private fun guessMimeType(path: String): String {
        val ext = path.substringAfterLast('.', "").lowercase()
        return when (ext) {
            "mp4", "m4v" -> "video/mp4"
            "mkv" -> "video/x-matroska"
            "webm" -> "video/webm"
            "mov" -> "video/quicktime"
            "mp3" -> "audio/mpeg"
            "m4a", "aac" -> "audio/aac"
            "flac" -> "audio/flac"
            "ogg", "oga" -> "audio/ogg"
            "opus" -> "audio/opus"
            "wav" -> "audio/wav"
            else -> "*/*"
        }
    }

    // ── helpers ─────────────────────────────────────────────────────────────

    /**
     * Apply a flat list of yt-dlp args (`["-o", "...", "-f", "best", ...]`) to
     * a `YoutubeDLRequest`. Pair entries are passed as option + value; bare
     * entries become flag-style options.
     */
    private fun applyArgs(request: YoutubeDLRequest, args: List<String>) {
        var i = 0
        while (i < args.size) {
            val token = args[i]
            if (!token.startsWith("-")) {
                // Positional / unexpected. yt-dlp will reject; we forward verbatim.
                request.addOption(token)
                i += 1
                continue
            }
            val next = args.getOrNull(i + 1)
            if (next == null || next.startsWith("-")) {
                request.addOption(token)
                i += 1
            } else {
                request.addOption(token, next)
                i += 2
            }
        }
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    private fun emitOnMain(event: Map<String, Any?>) {
        val sink = eventSink ?: return
        mainHandler.post {
            try {
                sink.success(event)
            } catch (_: Throwable) { /* sink is gone — drop event */ }
        }
    }

    companion object {
        private const val METHOD_CHANNEL = "down4more/yt_dlp"
        private const val EVENT_CHANNEL = "down4more/yt_dlp/events"

        // Error codes mirrored on the Dart side.
        private const val ERR_INIT = "init_failed"
        private const val ERR_ARG = "bad_arg"
        private const val ERR_YTDLP = "yt_dlp_failed"
        private const val ERR_CANCELLED = "cancelled"
        private const val ERR_UNKNOWN = "unknown"
        private const val ERR_EXPORT = "export_failed"
    }
}
