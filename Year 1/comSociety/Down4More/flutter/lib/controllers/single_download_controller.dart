import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/download_progress.dart';
import '../models/video_metadata.dart';
import '../services/ytdlp_service.dart';

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
  })  : _service = service ?? YtDlpService(),
        _defaultOutputDir = defaultOutputDir ?? _platformDownloadsDir;

  final YtDlpService _service;
  final Future<String> Function() _defaultOutputDir;

  DownloadProgress _progress = DownloadProgress.idle;
  VideoMetadata? _metadata;
  VideoFormat? _selectedFormat;
  DownloadHandle? _handle;
  StreamSubscription<DownloadProgress>? _progressSub;

  DownloadProgress get progress => _progress;
  VideoMetadata? get metadata => _metadata;
  VideoFormat? get selectedFormat => _selectedFormat;

  bool get isBusy =>
      _progress.phase == DownloadPhase.fetchingMetadata ||
      _progress.phase == DownloadPhase.downloading;

  /// Run yt-dlp metadata fetch. Updates [progress] through fetching → ready
  /// (or → error). Safe to call again to retry; resets all prior state.
  Future<void> fetchMetadata(String url) async {
    await _resetActiveDownload();
    _progress = const DownloadProgress(phase: DownloadPhase.fetchingMetadata);
    _metadata = null;
    _selectedFormat = null;
    notifyListeners();

    try {
      final m = await _service.fetchMetadata(url.trim());
      _metadata = m;
      _selectedFormat = m.formats.isNotEmpty ? m.defaultFormat : null;
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
    notifyListeners();
  }

  /// Kick off the actual download. No-op if there's no metadata + format yet.
  Future<void> startDownload() async {
    final m = _metadata;
    final f = _selectedFormat;
    if (m == null || f == null) return;
    if (_progress.phase == DownloadPhase.downloading) return;

    String dir;
    try {
      dir = await _defaultOutputDir();
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
    );
    _progressSub = _handle!.stream.listen((event) {
      _progress = event;
      notifyListeners();
    });
  }

  /// Send SIGTERM to the running yt-dlp process. The stream will then emit a
  /// [DownloadPhase.cancelled] event on its own.
  Future<void> cancel() async {
    await _handle?.cancel();
  }

  /// Discard everything and go back to the empty paste-a-URL state. Called
  /// from the UI's "Back to start" / "New download" actions.
  void reset() {
    _resetActiveDownload();
    _progress = DownloadProgress.idle;
    _metadata = null;
    _selectedFormat = null;
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
  final dir = Directory('${base.path}/Down4More');
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
  return Directory('$home/Downloads');
}
