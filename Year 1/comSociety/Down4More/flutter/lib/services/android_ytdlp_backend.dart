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
/// All yt-dlp argument-building mirrors [YtDlpService] verbatim so a video
/// downloaded on Android lands with the same filename / format / subtitle
/// treatment as on desktop. The platform-specific bits this backend layers
/// on top:
///
/// - **No subprocesses.** Every call goes through a [MethodChannel] /
///   [EventChannel] pair the plugin exposes.
/// - **Trim** (`trimStart` / `trimEnd`) uses yt-dlp's built-in
///   `--download-sections` flag instead of the desktop's
///   download-to-temp-then-ffmpeg dance, because youtubedl-android already
///   bundles ffmpeg and `--download-sections` works on it.
/// - **Fake pause/resume.** The library exposes no pause primitive, so
///   `pause()` calls `cancelDownload` and stashes the args + downloadId;
///   `resume()` re-issues `startDownload` with `--continue` appended so
///   yt-dlp picks up from the partial `.part` file. The user-facing button
///   keeps working — speed/ETA reset on resume and an in-progress merge
///   restarts from scratch (caveats surfaced in the UI tooltip).
/// - **MediaStore export.** yt-dlp writes to the app's external scratch
///   directory (no permission needed); on completion we ask the plugin to
///   copy the final file into the public `Movies/Down4More/` folder via
///   `MediaStore.Video.Media` / `MediaStore.Audio.Media`. The result is a
///   user-visible file that survives uninstall and shows up in the gallery.
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
    final session = _DownloadSession(
      backend: this,
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
      // Detect a "group folder" by treating any path segment after a
      // `Down4More` ancestor as one (so playlist / batch group folders flow
      // through to the public Movies/Down4More/<group>/ landing zone).
      mediaStoreSubfolder: _extractGroupFolder(outputDir),
    );
    session.start();
    return DownloadHandle.streamed(
      stream: session.stream,
      onCancel: session.cancel,
      onPause: session.pause,
      onResume: session.resume,
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
  ///
  /// [extraArgs] gets appended verbatim and is used by [_DownloadSession]
  /// to inject `--continue` on resume.
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
    List<String> extraArgs = const <String>[],
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
      ...extraArgs,
      metadata.url,
    ];
  }

  Future<Map<String, dynamic>?> _exportToMediaStore({
    required String srcPath,
    required String displayName,
    required String mimeType,
    required String? subfolder,
    required bool isAudio,
  }) async {
    try {
      final result = await _method.invokeMapMethod<dynamic, dynamic>(
        'exportToMediaStore',
        <String, dynamic>{
          'srcPath': srcPath,
          'displayName': displayName,
          'mimeType': mimeType,
          'subfolder': subfolder,
          'isAudio': isAudio,
        },
      );
      if (result == null) return null;
      return result.map<String, dynamic>(
        (k, v) => MapEntry(k.toString(), v),
      );
    } on PlatformException catch (_) {
      // MediaStore export failures are non-fatal: the file is still in
      // app scratch, so the download succeeded — we just couldn't make it
      // public. We surface the original scratch path to the user.
      return null;
    }
  }

  /// Ask the plugin to open a file by [path] using Android's
  /// `Intent.ACTION_VIEW`. Returns true on success.
  ///
  /// The plugin resolves a MediaStore content URI when the file lives in
  /// `Movies/Down4More/...` so the receiving viewer app gets a properly
  /// scoped URI rather than a raw `file://` (which Android blocks since
  /// API 24).
  @override
  Future<bool> openFile(String path) async {
    try {
      final ok = await _method.invokeMethod<bool>(
        'openFile',
        <String, dynamic>{'path': path},
      );
      return ok ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  /// Ask the plugin to reveal a file's containing folder. On Android the
  /// closest analogue is opening the Files app filtered to the parent
  /// MediaStore collection (Movies / Music). Returns true on success.
  @override
  Future<bool> openFolder(String path) async {
    try {
      final ok = await _method.invokeMethod<bool>(
        'openFolder',
        <String, dynamic>{'path': path},
      );
      return ok ?? false;
    } on PlatformException catch (_) {
      return false;
    }
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

  /// Pull the trailing "group folder" segment out of a desktop-shaped
  /// outputDir. Controllers compute these as `<base>/Down4More[/<group>]`,
  /// so anything after a `Down4More` ancestor is treated as the group
  /// folder. Returns null if the path doesn't include `Down4More` or if the
  /// terminal segment IS `Down4More` (i.e. no group folder).
  static String? _extractGroupFolder(String outputDir) {
    final segments =
        outputDir.split(RegExp(r'[\\/]+')).where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return null;
    final marker = segments.lastIndexOf('Down4More');
    if (marker == -1) return null;
    if (marker == segments.length - 1) return null;
    final tail = segments.sublist(marker + 1);
    if (tail.isEmpty) return null;
    return tail.join('/');
  }

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

/// Internal: one in-flight Android download.
///
/// Tracks its own [downloadId], event-stream subscription, and pause state
/// so [pause] / [resume] / [cancel] can be implemented as plain method
/// calls back from [DownloadHandle.streamed]. Pause is faked via
/// `cancelDownload` + a stashed args list; resume re-issues
/// `startDownload` with `--continue` appended so yt-dlp continues from the
/// `.part` file.
class _DownloadSession {
  _DownloadSession({
    required this.backend,
    required this.metadata,
    required this.format,
    required this.outputDir,
    required this.outputExt,
    required this.outputTemplate,
    required this.customFilename,
    required this.trimStart,
    required this.trimEnd,
    required this.rateLimit,
    required this.keepPartial,
    required this.subtitles,
    required this.mediaStoreSubfolder,
  });

  final AndroidYtDlpBackend backend;
  final VideoMetadata metadata;
  final VideoFormat format;
  final String outputDir;
  final String outputExt;
  final String outputTemplate;
  final String? customFilename;
  final Duration? trimStart;
  final Duration? trimEnd;
  final String? rateLimit;
  final bool keepPartial;
  final SubtitleSettings? subtitles;
  final String? mediaStoreSubfolder;

  final StreamController<DownloadProgress> _controller =
      StreamController<DownloadProgress>.broadcast();

  String? _currentDownloadId;
  StreamSubscription<Map<String, dynamic>>? _subscription;

  // Sticky progress fields carried forward between progress lines and used
  // to build the synthetic "paused" progress event.
  double _lastPercent = 0;
  int? _totalBytes;
  double? _speedBytesPerSecond;
  Duration? _eta;
  String? _outputPath;

  bool _paused = false;
  bool _cancelled = false;
  bool _finished = false;
  bool _merging = false;

  Stream<DownloadProgress> get stream => _controller.stream;

  void start() {
    final args = backend._buildDownloadArgs(
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
    _spawn(args);
  }

  void pause() {
    if (_paused || _cancelled || _finished) return;
    _paused = true;
    final id = _currentDownloadId;
    if (id != null) {
      backend._method.invokeMethod<void>(
        'cancelDownload',
        <String, dynamic>{'downloadId': id},
      ).catchError((_) {/* swallow — already cancelled */});
    }
    // Emit a synthetic paused-downloading event immediately so the UI
    // doesn't have to wait for the Kotlin-side cancelled event to arrive.
    if (!_controller.isClosed) {
      _controller.add(DownloadProgress(
        phase: DownloadPhase.downloading,
        paused: true,
        percent: _lastPercent,
        totalBytes: _totalBytes,
        speedBytesPerSecond: _speedBytesPerSecond,
        eta: _eta,
        outputPath: _outputPath,
      ));
    }
  }

  void resume() {
    if (!_paused || _cancelled || _finished) return;
    _paused = false;
    final args = backend._buildDownloadArgs(
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
      // Tell yt-dlp to pick up from the .part file rather than start over.
      extraArgs: const ['--continue'],
    );
    _spawn(args);
    // Re-emit a non-paused progress event so the UI updates promptly.
    if (!_controller.isClosed) {
      _controller.add(DownloadProgress(
        phase: DownloadPhase.downloading,
        paused: false,
        percent: _lastPercent,
        totalBytes: _totalBytes,
        speedBytesPerSecond: _speedBytesPerSecond,
        eta: _eta,
        outputPath: _outputPath,
      ));
    }
  }

  void cancel() {
    if (_cancelled || _finished) return;
    _cancelled = true;
    // If we're paused there's no Kotlin-side download to kill — the previous
    // one was already cancelled when pause() ran. Emit the cancelled event
    // synthetically and close.
    if (_paused) {
      _paused = false;
      if (!_controller.isClosed) {
        _controller.add(const DownloadProgress(phase: DownloadPhase.cancelled));
        _controller.close();
      }
      _subscription?.cancel();
      _subscription = null;
      return;
    }
    final id = _currentDownloadId;
    if (id != null) {
      backend._method.invokeMethod<void>(
        'cancelDownload',
        <String, dynamic>{'downloadId': id},
      ).catchError((_) {/* swallow — already cancelled */});
    }
    // The Kotlin side will emit a `cancelled` event that the listener
    // forwards. No synthetic emit here — we want the event to land naturally.
  }

  /// Spin up a new Kotlin-side download and (re)subscribe the event stream.
  /// Used by both [start] and [resume].
  void _spawn(List<String> args) {
    final id = backend._generateDownloadId();
    _currentDownloadId = id;
    // Replace any prior subscription (resume case) so we only listen to the
    // current downloadId.
    _subscription?.cancel();
    _subscription = backend._eventBus
        .where((e) => e['downloadId'] == id)
        .listen(_onEvent);
    _controller.onCancel = () {
      _subscription?.cancel();
      _subscription = null;
    };

    unawaited(() async {
      try {
        await backend._ensureInitialized();
        await backend._method
            .invokeMethod<void>('startDownload', <String, dynamic>{
          'downloadId': id,
          'url': metadata.url,
          'args': args,
        });
      } catch (e) {
        if (_controller.isClosed || _cancelled) return;
        _controller.add(DownloadProgress(
          phase: DownloadPhase.error,
          errorMessage:
              backend._errorMessage(e, fallback: 'Failed to start download'),
        ));
        await _controller.close();
      }
    }());
  }

  void _onEvent(Map<String, dynamic> event) {
    final type = event['type'] as String?;
    switch (type) {
      case 'progress':
        _handleProgress(event);
        break;
      case 'completed':
        _handleCompleted(event);
        break;
      case 'error':
        _handleError(event);
        break;
      case 'cancelled':
        _handleCancelled();
        break;
    }
  }

  void _handleProgress(Map<String, dynamic> event) {
    final raw = event['line'] as String?;
    final parsed = raw == null ? null : parseProgressLine(raw);
    if (parsed != null) {
      // Detect the [Merger] line and lock to the merging state so
      // subsequent numeric-only callbacks don't overwrite the message.
      if (parsed.message != null &&
          parsed.message!.startsWith('Merging')) {
        _merging = true;
      }
      _lastPercent = parsed.percent ?? _lastPercent;
      _totalBytes = parsed.totalBytes ?? _totalBytes;
      _speedBytesPerSecond =
          parsed.speedBytesPerSecond ?? _speedBytesPerSecond;
      _eta = parsed.eta ?? _eta;
      _outputPath = parsed.outputPath ?? _outputPath;
      if (!_controller.isClosed && !_paused) _controller.add(parsed);
      return;
    }
    // Once merging has started, suppress the numeric-only fallback events
    // so the "Merging audio + video…" message stays visible.
    if (_merging) return;
    // No parseable line — fall back to the numeric percent / eta the
    // library callback gave us directly so the UI's progress bar still
    // ticks even when yt-dlp's stdout is silent.
    final percent = (event['percent'] as num?)?.toDouble() ?? _lastPercent;
    // Filter out negative percentages (the library reports -1 before any
    // real progress is available).
    if (percent < 0) return;
    final etaSec = (event['etaSeconds'] as num?)?.toInt();
    _lastPercent = percent;
    if (etaSec != null && etaSec > 0) _eta = Duration(seconds: etaSec);
    if (_controller.isClosed || _paused) return;
    _controller.add(DownloadProgress(
      phase: DownloadPhase.downloading,
      percent: percent,
      totalBytes: _totalBytes,
      speedBytesPerSecond: _speedBytesPerSecond,
      eta: _eta,
      outputPath: _outputPath,
    ));
  }

  Future<void> _handleCompleted(Map<String, dynamic> event) async {
    final exitCode = (event['exitCode'] as num?)?.toInt() ?? -1;
    if (exitCode != 0) {
      final stderr = (event['stderr'] as String?)?.trim() ?? '';
      if (!_controller.isClosed) {
        _controller.add(DownloadProgress(
          phase: DownloadPhase.error,
          errorMessage: stderr.isEmpty
              ? 'yt-dlp exited with code $exitCode.'
              : stderr,
        ));
        await _controller.close();
      }
      return;
    }
    _finished = true;
    // Best-effort MediaStore export. If it fails the user still has the
    // file in the app's scratch dir, which we surface as outputPath.
    final scratchPath = _outputPath;
    String publicPath = scratchPath ?? '';
    if (scratchPath != null && scratchPath.isNotEmpty) {
      final exported = await backend._exportToMediaStore(
        srcPath: scratchPath,
        displayName: p.basename(scratchPath),
        mimeType: _mimeTypeFor(scratchPath),
        subfolder: mediaStoreSubfolder,
        isAudio: format.isAudioOnly,
      );
      if (exported != null) {
        publicPath = (exported['displayPath'] as String?) ?? scratchPath;
      }
    }
    if (!_controller.isClosed) {
      _controller.add(DownloadProgress(
        phase: DownloadPhase.finished,
        percent: 100,
        outputPath: publicPath,
      ));
      await _controller.close();
    }
  }

  void _handleError(Map<String, dynamic> event) {
    if (_paused) {
      // We don't expect errors from Kotlin while paused (we cancelled it),
      // but if one slips through we treat it like any other error and stop.
      _paused = false;
    }
    if (_controller.isClosed) return;
    _controller.add(DownloadProgress(
      phase: DownloadPhase.error,
      errorMessage: (event['message'] as String?) ?? 'Unknown error.',
    ));
    _controller.close();
  }

  void _handleCancelled() {
    if (_paused) {
      // Expected: pause() asked Kotlin to cancel. Swallow the event — the
      // synthetic paused state was already emitted in pause().
      return;
    }
    if (_controller.isClosed) return;
    _controller.add(const DownloadProgress(phase: DownloadPhase.cancelled));
    _controller.close();
  }

  String _mimeTypeFor(String path) {
    final ext = p.extension(path).toLowerCase().replaceFirst('.', '');
    switch (ext) {
      case 'mp4':
      case 'm4v':
        return 'video/mp4';
      case 'mkv':
        return 'video/x-matroska';
      case 'webm':
        return 'video/webm';
      case 'mov':
        return 'video/quicktime';
      case 'mp3':
        return 'audio/mpeg';
      case 'm4a':
      case 'aac':
        return 'audio/aac';
      case 'flac':
        return 'audio/flac';
      case 'ogg':
      case 'oga':
        return 'audio/ogg';
      case 'opus':
        return 'audio/opus';
      case 'wav':
        return 'audio/wav';
      default:
        return format.isAudioOnly ? 'audio/*' : 'video/*';
    }
  }
}
