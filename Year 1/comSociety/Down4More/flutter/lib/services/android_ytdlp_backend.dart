import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../models/download_progress.dart';
import '../models/playlist_entry.dart';
import '../models/subtitle_settings.dart';
import '../models/video_metadata.dart';
import 'download_backend.dart';
import 'ytdlp_service.dart' show parseProgressLine;

/// Real Android [DownloadBackend] backed by the `youtubedl-android` JVM
/// library through the [YtDlpPlugin] (`android/app/src/main/kotlin/.../YtDlpPlugin.kt`).
///
/// All argument-building mirrors [YtDlpService] verbatim so a video downloaded
/// on Android lands with the same filename / format / subtitle treatment as on
/// desktop. The only differences:
///
/// - We never shell out to the host system — every call goes through a
///   [MethodChannel] / [EventChannel] pair the plugin exposes.
/// - Trim (`trimStart` / `trimEnd`) uses yt-dlp's built-in
///   `--download-sections` flag instead of the desktop's
///   download-to-temp-then-ffmpeg dance, because youtubedl-android already
///   bundles ffmpeg and `--download-sections` works on it.
/// - Pause / resume are no-ops on Android for now: youtubedl-android doesn't
///   expose a pause primitive. Cancel works and is wired through.
class AndroidYtDlpBackend implements DownloadBackend {
  AndroidYtDlpBackend({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  })  : _method = methodChannel ?? const MethodChannel('down4more/yt_dlp'),
        _events = eventChannel ?? const EventChannel('down4more/yt_dlp/events');

  final MethodChannel _method;
  final EventChannel _events;

  /// Demuxed broadcast view of the platform event channel so multiple
  /// concurrent downloads can each filter for their own [downloadId].
  /// Lazily constructed because [Stream.asBroadcastStream] without a
  /// downstream listener silently drops events.
  Stream<Map<String, dynamic>>? _eventsStream;
  Stream<Map<String, dynamic>> get _eventBus {
    return _eventsStream ??= _events
        .receiveBroadcastStream()
        .map<Map<String, dynamic>>(_coerceEventMap)
        .asBroadcastStream();
  }

  /// Initialised lazily on the first method call. Wrapped in a future so
  /// concurrent first-callers all await the same init() round-trip.
  Future<void>? _initFuture;
  Future<void> _ensureInitialized() {
    return _initFuture ??= _method.invokeMethod<void>('init').catchError((e) {
      // Reset so a future retry can re-init (the user might fix a permission
      // and try again instead of getting stuck on a cached failure).
      _initFuture = null;
      throw YtDlpException(_errorMessage(e, fallback: 'init failed'));
    });
  }

  // ── DownloadBackend implementation ────────────────────────────────────

  @override
  Future<VideoMetadata> fetchMetadata(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) throw YtDlpException('URL is empty.');
    await _ensureInitialized();
    final stdout = await _runYtDlpSync(
      url: trimmed,
      args: const <String>[
        '--dump-single-json',
        '--no-warnings',
        '--no-cache-dir',
      ],
      label: 'metadata',
    );
    try {
      final decoded = jsonDecode(stdout.trim()) as Map<String, dynamic>;
      return VideoMetadata.fromJson(trimmed, decoded);
    } on FormatException catch (e) {
      throw YtDlpException("Couldn't parse yt-dlp's JSON output: ${e.message}");
    }
  }

  @override
  Future<List<PlaylistEntry>> fetchPlaylist(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) throw YtDlpException('URL is empty.');
    await _ensureInitialized();
    final stdout = await _runYtDlpSync(
      url: trimmed,
      args: const <String>[
        '--flat-playlist',
        '--dump-json',
        '--no-warnings',
      ],
      label: 'playlist',
    );
    final entries = <PlaylistEntry>[];
    for (final line in stdout.trim().split('\n')) {
      if (line.trim().isEmpty) continue;
      try {
        final json = jsonDecode(line) as Map<String, dynamic>;
        final entry = PlaylistEntry.fromJson(json);
        if (entry.url.isNotEmpty) entries.add(entry);
      } catch (_) {
        continue;
      }
    }
    return entries;
  }

  @override
  Future<String?> getPlaylistTitle(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;
    try {
      await _ensureInitialized();
      final stdout = await _runYtDlpSync(
        url: trimmed,
        args: const <String>[
          '--flat-playlist',
          '--print',
          '%(playlist_title|)s',
          '--no-warnings',
          '--playlist-items',
          '1',
        ],
        label: 'playlist-title',
      );
      for (final line in stdout.split('\n')) {
        final t = line.trim();
        if (t.isNotEmpty && t != 'NA') return t;
      }
      return null;
    } on YtDlpException {
      // Best-effort: never fail the playlist fetch over a missing title.
      return null;
    }
  }

  @override
  DownloadHandle download({
    required VideoMetadata metadata,
    required VideoFormat format,
    required String outputDir,
    String outputExt = 'mp4',
    String outputTemplate = '%(title).200B.%(ext)s',
    String? customFilename,
    Duration? trimStart,
    Duration? trimEnd,
    String? rateLimit,
    bool keepPartial = false,
    SubtitleSettings? subtitles,
  }) {
    final controller = StreamController<DownloadProgress>.broadcast();
    final downloadId = _generateDownloadId();

    final args = _buildDownloadArgs(
      metadata: metadata,
      format: format,
      outputDir: outputDir,
      outputExt: outputExt,
      outputTemplate: outputTemplate,
      customFilename: customFilename,
      trimStart: trimStart,
      trimEnd: trimEnd,
      rateLimit: rateLimit,
      keepPartial: keepPartial,
      subtitles: subtitles,
    );

    // Capture the most recently parsed line so we can carry forward
    // outputPath / totalBytes once yt-dlp moves past the [download] phase.
    double lastPercent = 0;
    int? totalBytes;
    double? speedBytesPerSecond;
    Duration? eta;
    String? outputPath;

    final subscription = _eventBus
        .where((e) => e['downloadId'] == downloadId)
        .listen((event) {
      final type = event['type'] as String?;
      switch (type) {
        case 'progress':
          final raw = event['line'] as String?;
          final parsed = raw == null ? null : parseProgressLine(raw);
          if (parsed != null) {
            lastPercent = parsed.percent ?? lastPercent;
            totalBytes = parsed.totalBytes ?? totalBytes;
            speedBytesPerSecond =
                parsed.speedBytesPerSecond ?? speedBytesPerSecond;
            eta = parsed.eta ?? eta;
            outputPath = parsed.outputPath ?? outputPath;
            controller.add(parsed);
          } else {
            // No parseable line — fall back to the numeric percent / eta the
            // library callback gave us directly so the UI's progress bar
            // still ticks even when yt-dlp's stdout is silent.
            final percent =
                (event['percent'] as num?)?.toDouble() ?? lastPercent;
            final etaSec = (event['etaSeconds'] as num?)?.toInt();
            lastPercent = percent;
            if (etaSec != null && etaSec > 0) eta = Duration(seconds: etaSec);
            controller.add(
              DownloadProgress(
                phase: DownloadPhase.downloading,
                percent: percent,
                totalBytes: totalBytes,
                speedBytesPerSecond: speedBytesPerSecond,
                eta: eta,
                outputPath: outputPath,
              ),
            );
          }
          break;

        case 'completed':
          final exitCode = (event['exitCode'] as num?)?.toInt() ?? -1;
          if (exitCode == 0) {
            controller.add(
              DownloadProgress(
                phase: DownloadPhase.finished,
                percent: 100,
                outputPath: outputPath,
              ),
            );
          } else {
            final stderr = (event['stderr'] as String?)?.trim() ?? '';
            controller.add(
              DownloadProgress(
                phase: DownloadPhase.error,
                errorMessage: stderr.isEmpty
                    ? 'yt-dlp exited with code $exitCode.'
                    : stderr,
              ),
            );
          }
          controller.close();
          break;

        case 'error':
          controller.add(
            DownloadProgress(
              phase: DownloadPhase.error,
              errorMessage: (event['message'] as String?) ?? 'Unknown error.',
            ),
          );
          controller.close();
          break;

        case 'cancelled':
          controller.add(
            const DownloadProgress(phase: DownloadPhase.cancelled),
          );
          controller.close();
          break;
      }
    });

    // Tear down the EventChannel listener whenever the stream is no longer
    // being observed (everyone unsubscribed) so we don't leak.
    controller.onCancel = subscription.cancel;

    // Kick off the download asynchronously; the handle is returned
    // synchronously and progress is streamed through the EventChannel.
    unawaited(() async {
      try {
        await _ensureInitialized();
        await _method.invokeMethod<void>('startDownload', <String, dynamic>{
          'downloadId': downloadId,
          'url': metadata.url,
          'args': args,
        });
      } catch (e) {
        if (controller.isClosed) return;
        controller.add(
          DownloadProgress(
            phase: DownloadPhase.error,
            errorMessage:
                _errorMessage(e, fallback: 'Failed to start download'),
          ),
        );
        await controller.close();
      }
    }());

    return DownloadHandle.streamed(
      stream: controller.stream,
      onCancel: () {
        _method
            .invokeMethod<void>('cancelDownload', <String, dynamic>{
              'downloadId': downloadId,
            })
            .catchError((_) {/* swallow — Kotlin already emitted */});
      },
      // youtubedl-android can't pause; the UI's pause/resume buttons
      // are gated separately. We leave these as no-ops so callers can
      // still invoke them without crashing.
      onPause: () {},
      onResume: () {},
    );
  }

  // ── helpers ───────────────────────────────────────────────────────────

  Future<String> _runYtDlpSync({
    required String url,
    required List<String> args,
    required String label,
  }) async {
    final Map<dynamic, dynamic>? result;
    try {
      result = await _method
          .invokeMapMethod<dynamic, dynamic>('getInfo', <String, dynamic>{
        'url': url,
        'args': args,
      });
    } on PlatformException catch (e) {
      throw YtDlpException(_errorMessage(e, fallback: '$label fetch failed'));
    }
    if (result == null) {
      throw YtDlpException('yt-dlp returned no $label response.');
    }
    final exitCode = (result['exitCode'] as num?)?.toInt() ?? -1;
    final stderr = (result['stderr'] as String?)?.trim() ?? '';
    if (exitCode != 0) {
      throw YtDlpException(
        stderr.isEmpty
            ? 'yt-dlp exited with code $exitCode.'
            : stderr,
      );
    }
    return (result['stdout'] as String?) ?? '';
  }

  /// Build the exact same yt-dlp args list [YtDlpService.download] would
  /// build for the desktop backend, minus the host-side trim/temp-file
  /// dance — on Android we hand trimming straight to yt-dlp via
  /// `--download-sections`, since youtubedl-android already ships ffmpeg.
  List<String> _buildDownloadArgs({
    required VideoMetadata metadata,
    required VideoFormat format,
    required String outputDir,
    required String outputExt,
    required String outputTemplate,
    required String? customFilename,
    required Duration? trimStart,
    required Duration? trimEnd,
    required String? rateLimit,
    required bool keepPartial,
    required SubtitleSettings? subtitles,
  }) {
    final isAudio = format.isAudioOnly;
    final ytdlpAudioFmt = outputExt == 'ogg' ? 'vorbis' : outputExt;
    final effectiveTemplate = (customFilename != null &&
            customFilename.isNotEmpty)
        ? '${_sanitizeFilename(customFilename)}.%(ext)s'
        : outputTemplate;

    final subtitleArgs = <String>[];
    if (subtitles != null &&
        subtitles.enabled &&
        subtitles.language.trim().isNotEmpty) {
      final lang = subtitles.language.trim();
      final fmt =
          subtitles.format.trim().isEmpty ? 'srt' : subtitles.format.trim();
      final canEmbed = !isAudio && _embedSubsExts.contains(outputExt);
      if (subtitles.useAutoCaption) {
        subtitleArgs.addAll([
          '--write-auto-subs',
          if (subtitles.embed && canEmbed) '--write-subs',
          '--sub-langs', lang,
          '--sub-format', '$fmt/best',
          '--convert-subs', fmt,
          if (subtitles.embed && canEmbed) '--embed-subs',
          '--sleep-subtitles', '1',
        ]);
      } else {
        subtitleArgs.addAll([
          '--write-subs',
          '--sub-langs', lang,
          '--sub-format', '$fmt/best',
          '--convert-subs', fmt,
          if (subtitles.embed && canEmbed) '--embed-subs',
          '--sleep-subtitles', '1',
        ]);
      }
    }

    final trimArgs = <String>[];
    if (trimStart != null || trimEnd != null) {
      final start = trimStart ?? Duration.zero;
      final end = trimEnd ?? metadata.duration;
      // `*HH:MM:SS-HH:MM:SS` is yt-dlp's "absolute time range" syntax.
      // We omit the end side when we don't have a duration; yt-dlp accepts
      // an open-ended range as "from start to end of stream".
      final range = end == null
          ? '*${_formatTrim(start)}-'
          : '*${_formatTrim(start)}-${_formatTrim(end)}';
      trimArgs.addAll(['--download-sections', range, '--force-keyframes-at-cuts']);
    }

    return <String>[
      '--newline',
      '--no-playlist',
      '--no-warnings',
      '--no-cache-dir',
      if (!keepPartial) '--no-part',
      '-f', format.id,
      if (isAudio) ...['-x', '--audio-format', ytdlpAudioFmt]
      else ...['--merge-output-format', outputExt],
      if (rateLimit != null && rateLimit.isNotEmpty)
        ...['--rate-limit', rateLimit],
      ...subtitleArgs,
      ...trimArgs,
      '-o', p.join(outputDir, effectiveTemplate),
      metadata.url,
    ];
  }

  // ── small utilities ───────────────────────────────────────────────────

  String _generateDownloadId() {
    // Plenty of entropy for any plausible UI usage — we never collide with
    // ourselves inside a single process.
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final seq = _idSequence++;
    return 'd4m-$stamp-$seq';
  }

  static int _idSequence = 0;

  static String _sanitizeFilename(String input) {
    // Mirror the desktop service's tolerance: strip path separators + control
    // chars but otherwise leave the user's input alone.
    return input
        .replaceAll(RegExp(r'[\x00-\x1f\\/:*?"<>|]'), '_')
        .trim();
  }

  static String _formatTrim(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(h)}:${two(m)}:${two(s)}';
  }

  /// Containers we know how to mux subtitles into. Kept here rather than
  /// imported to avoid coupling to ytdlp_service.dart's private constant.
  static const Set<String> _embedSubsExts = {'mp4', 'mkv'};

  Map<String, dynamic> _coerceEventMap(dynamic raw) {
    if (raw is Map) {
      return raw.map<String, dynamic>(
        (k, v) => MapEntry(k.toString(), v),
      );
    }
    return <String, dynamic>{};
  }

  String _errorMessage(Object error, {required String fallback}) {
    if (error is PlatformException) {
      final detail = (error.message ?? '').trim();
      return detail.isEmpty ? fallback : detail;
    }
    final s = error.toString().trim();
    return s.isEmpty ? fallback : s;
  }
}
