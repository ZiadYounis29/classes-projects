package com.ziadyounis.down4more.down4more

import android.content.Context
import com.yausername.ffmpeg.FFmpeg
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLException
import com.yausername.youtubedl_android.YoutubeDLRequest
import com.yausername.youtubedl_android.YoutubeDLResponse
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
import java.util.concurrent.ConcurrentHashMap

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
            else -> result.notImplemented()
        }
    }

    // ── init ────────────────────────────────────────────────────────────────

    private fun ensureInitialized() {
        if (initialized) return
        synchronized(this) {
            if (initialized) return
            YoutubeDL.getInstance().init(context)
            FFmpeg.getInstance().init(context)
            initialized = true
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
            }
        }
        downloadJobs[downloadId] = job
        // Acknowledge immediately so the Dart side can start listening on the
        // EventChannel before the first progress tick lands.
        result.success(null)
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
        downloadJobs[downloadId]?.cancel()
        downloadJobs.remove(downloadId)
        emitOnMain(mapOf("downloadId" to downloadId, "type" to "cancelled"))
        result.success(null)
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

    private fun emitOnMain(event: Map<String, Any?>) {
        // EventSink.success must be called on the platform-thread / main
        // thread. We dispatch via the channel's handler which already does
        // this internally — wrap in a try because the sink may have been
        // torn down while a coroutine was still running.
        try {
            eventSink?.success(event)
        } catch (_: Throwable) { /* sink is gone — drop event */ }
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
    }
}
