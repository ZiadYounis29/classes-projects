import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/download_progress.dart';
import '../models/output_format.dart';
import '../models/video_metadata.dart';
import '../services/ytdlp_service.dart';
import '../settings/app_settings.dart';

/// Owns the state of *one* single-URL download flow: typing → fetching
/// metadata → picking a quality → downloading → finished/error/cancelled.
///
/// Listened to by [SingleScreen] via [ListenableBuilder]. Kept as a plain
/// [ChangeNotifier] (no Provider/Riverpod) since there's only one of these and
/// it's owned directly by its screen.
class SingleDownloadController extends ChangeNotifier {
  SingleDownloadController({
    YtDlpService? service,
    Future<String> Function()? defaultOutputDir,
    AppSettings? appSettings,
  })  : _service = service ?? YtDlpService(),
        _defaultOutputDir = defaultOutputDir ?? _platformDownloadsDir,
        _appSettings = appSettings;

  final YtDlpService _service;
  final Future<String> Function() _defaultOutputDir;
  final AppSettings? _appSettings;

  DownloadProgress _progress = DownloadProgress.idle;
  VideoMetadata? _metadata;
  VideoFormat? _selectedFormat;
  OutputFormat _selectedOutputFormat = kDefaultVideoFormat;
  Duration? _trimStart;
  Duration? _trimEnd;
  String _customFilename = '';
  bool _filenameManuallyEdited = false;
  DownloadHandle? _handle;
  StreamSubscription<DownloadProgress>? _progressSub;
  int _retryAttempt = 0;

  DownloadProgress get progress => _progress;
  VideoMetadata? get metadata => _metadata;
  VideoFormat? get selectedFormat => _selectedFormat;
  OutputFormat get selectedOutputFormat => _selectedOutputFormat;
  Duration? get trimStart => _trimStart;
  Duration? get trimEnd => _trimEnd;
  String get customFilename => _customFilename;

  bool get isBusy =>
      _progress.phase == DownloadPhase.fetchingMetadata ||
      _progress.phase == DownloadPhase.downloading;

  bool get isPaused => _progress.paused;

  /// Run yt-dlp metadata fetch. Updates [progress] through fetching → ready
  /// (or → error). Safe to call again to retry; resets all prior state.
  Future<void> fetchMetadata(String url) async {
    await _resetActiveDownload();
    _progress = const DownloadProgress(phase: DownloadPhase.fetchingMetadata);
    _metadata = null;
    _selectedFormat = null;
    _selectedOutputFormat = kDefaultVideoFormat;
    _trimStart = null;
    _trimEnd = null;
    _retryAttempt = 0;
    notifyListeners();

    try {
      final m = await _service.fetchMetadata(url.trim());
      _metadata = m;
      _selectedFormat = m.formats.isNotEmpty ? m.defaultFormat : null;
      // If the default format is audio-only, switch the output format default.
      if (_selectedFormat?.isAudioOnly == true) {
        _selectedOutputFormat = kDefaultAudioFormat;
      }
      _customFilename = m.title;
      _filenameManuallyEdited = false;
      _progress = const DownloadProgress(phase: DownloadPhase.ready);
    } on YtDlpException catch (e) {
      _progress = DownloadProgress(
        phase: DownloadPhase.error,
        errorMessage: e.message,
      );
    } catch (e) {
      _progress = DownloadProgress(
        phase: DownloadPhase.error,
        errorMessage: 'Unexpected error: $e',
      );
    }
    notifyListeners();
  }

  void selectFormat(VideoFormat format) {
    if (_selectedFormat?.id == format.id) return;
    _selectedFormat = format;
    // When the user switches between a video quality and audio-only (or vice
    // versa), snap the output format to a sensible default for that category
    // so the two dropdowns stay in sync automatically.
    if (format.isAudioOnly &&
        _selectedOutputFormat.category == OutputCategory.video) {
      _selectedOutputFormat = kDefaultAudioFormat;
    } else if (!format.isAudioOnly &&
        _selectedOutputFormat.category == OutputCategory.audio) {
      _selectedOutputFormat = kDefaultVideoFormat;
    }
    notifyListeners();
  }

  void selectOutputFormat(OutputFormat fmt) {
    if (_selectedOutputFormat == fmt) return;
    _selectedOutputFormat = fmt;
    notifyListeners();
  }

  /// Set the custom filename. Marks it as manually edited so trim changes
  /// won't overwrite the user's choice.
  void setCustomFilename(String name) {
    _customFilename = name;
    _filenameManuallyEdited = true;
    notifyListeners();
  }

  /// Update the trim window. Pass null to clear a boundary.
  /// Silently ignores invalid combinations (start >= end) — the UI widget
  /// validates before calling this.
  void setTrim({Duration? start, Duration? end}) {
    _trimStart = start;
    _trimEnd = end;
    // Auto-update filename with trim range unless user manually edited it.
    if (!_filenameManuallyEdited && _metadata != null) {
      _updateAutoFilename();
    }
    notifyListeners();
  }

  void _updateAutoFilename() {
    final title = _metadata?.title ?? '';
    if (_trimStart != null || _trimEnd != null) {
      final startStr = _formatTrimLabel(_trimStart ?? Duration.zero);
      final endStr = _formatTrimLabel(
          _trimEnd ?? _metadata?.duration ?? Duration.zero);
      _customFilename = '$title [$startStr-$endStr]';
    } else {
      _customFilename = title;
    }
  }

  static String _formatTrimLabel(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (h > 0) return '${h}h${m}m${s}s';
    return '${m}m${s}s';
  }

  /// Kick off the actual download. No-op if there's no metadata + format yet.
  Future<void> startDownload() async {
    final m = _metadata;
    final f = _selectedFormat;
    if (m == null || f == null) return;
    if (_progress.phase == DownloadPhase.downloading) return;

    // Resolve output directory: custom setting > platform default.
    String dir;
    try {
      final custom = _appSettings?.downloadDir ?? '';
      if (custom.isNotEmpty) {
        final d = Directory(custom);
        if (!await d.exists()) await d.create(recursive: true);
        dir = custom;
      } else {
        dir = await _defaultOutputDir();
      }
    } catch (e) {
      _progress = DownloadProgress(
        phase: DownloadPhase.error,
        errorMessage: "Couldn't resolve a download folder: $e",
      );
      notifyListeners();
      return;
    }

    _handle = _service.download(
      metadata: m,
      format: f,
      outputDir: dir,
      outputExt: _selectedOutputFormat.ext,
      customFilename: _customFilename.isNotEmpty ? _customFilename : null,
      trimStart: _trimStart,
      trimEnd: _trimEnd,
      rateLimit: _appSettings?.hasSpeedLimit == true
          ? _appSettings!.speedLimit
          : null,
    );
    _progressSub = _handle!.stream.listen((event) {
      _progress = event;
      notifyListeners();

      // Auto-retry on error if configured.
      if (event.phase == DownloadPhase.error) {
        final maxRetries = _appSettings?.autoRetry ?? 0;
        if (_retryAttempt < maxRetries) {
          _retryAttempt++;
          final delay = _appSettings?.retryDelay ?? 5;
          Future.delayed(Duration(seconds: delay), () {
            if (_progress.phase == DownloadPhase.error) {
              startDownload();
            }
          });
        }
      } else if (event.phase == DownloadPhase.finished) {
        _retryAttempt = 0;
      }
    });
  }

  /// Send SIGTERM to the running yt-dlp process. The stream will then emit a
  /// [DownloadPhase.cancelled] event on its own.
  Future<void> cancel() async {
    await _handle?.cancel();
  }

  /// Pause the active download. No-op if not currently downloading.
  void pause() {
    if (_progress.phase != DownloadPhase.downloading) return;
    if (_progress.paused) return;
    _handle?.pause();
  }

  /// Resume a paused download. No-op if not paused.
  void resume() {
    if (!_progress.paused) return;
    _handle?.resume();
  }

  /// Discard everything and go back to the empty paste-a-URL state. Called
  /// from the UI's "Back to start" / "New download" actions.
  void reset() {
    _resetActiveDownload();
    _progress = DownloadProgress.idle;
    _metadata = null;
    _selectedFormat = null;
    _selectedOutputFormat = kDefaultVideoFormat;
    _trimStart = null;
    _trimEnd = null;
    _customFilename = '';
    _filenameManuallyEdited = false;
    _retryAttempt = 0;
    notifyListeners();
  }

  Future<void> _resetActiveDownload() async {
    await _progressSub?.cancel();
    _progressSub = null;
    await _handle?.cancel();
    _handle = null;
  }

  @override
  void dispose() {
    _resetActiveDownload();
    super.dispose();
  }
}

/// Resolve the user's default Down4More download folder. We prefer the
/// platform's native Downloads directory + a `Down4More/` subfolder so files
/// don't get lost in a sea of other downloads. Creates the folder if missing.
Future<String> _platformDownloadsDir() async {
  Directory? base;
  try {
    base = await getDownloadsDirectory();
  } catch (_) {
    base = null;
  }
  // path_provider's `getDownloadsDirectory` is null on Android & some Linux
  // setups. Fall back to ~/Downloads (POSIX) / %USERPROFILE%\Downloads (Win).
  base ??= _fallbackDownloadsDir();

  // Always create the Down4More subfolder, regardless of which base we got.
  final dir = Directory(p.join(base.path, 'Down4More'));
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir.path;
}

Directory _fallbackDownloadsDir() {
  final home = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
  if (home == null) {
    // Worst case: just use the current working directory. Not ideal but
    // never crashes.
    return Directory.current;
  }
  return Directory(p.join(home, 'Downloads'));
}
