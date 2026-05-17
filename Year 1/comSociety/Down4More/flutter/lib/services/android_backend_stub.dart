import '../models/playlist_entry.dart';
import '../models/subtitle_settings.dart';
import '../models/video_metadata.dart';
import 'download_backend.dart';

/// Placeholder [DownloadBackend] used on Android until the real backend
/// (built on top of the `youtubedl-android` JVM library) is wired up.
///
/// On Android there is no yt-dlp / ffmpeg CLI to shell out to \u2014 yt-dlp is
/// Python and ffmpeg is C, and the Android runtime can't spawn arbitrary
/// subprocesses anyway. Until the platform-channel backend lands, controllers
/// running on Android receive an instance of this stub. Every operation
/// surfaces a single, descriptive error so the UI's existing error-card path
/// is exercised cleanly instead of an uncaught exception leaking through.
///
/// This is intentionally `const`-constructible so the factory can return a
/// shared singleton without per-call allocation.
class AndroidBackendStub implements DownloadBackend {
  const AndroidBackendStub();

  /// Public so unit tests can assert against the exact message the user
  /// would see.
  static const String unsupportedMessage =
      'Downloading on Android is not implemented yet. '
      "It's coming in a follow-up PR that wires the youtubedl-android library "
      'in as a native backend. Please use the desktop build for now.';

  @override
  Future<VideoMetadata> fetchMetadata(String url) {
    throw YtDlpException(unsupportedMessage);
  }

  @override
  Future<List<PlaylistEntry>> fetchPlaylist(String url) {
    throw YtDlpException(unsupportedMessage);
  }

  /// Returns `null` rather than throwing so callers that fall back to a
  /// default playlist name (see [PlaylistController.fetch]) don't surface a
  /// spurious error before the user has even hit Download. The real failure
  /// happens on [fetchPlaylist] / [download].
  @override
  Future<String?> getPlaylistTitle(String url) async => null;

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
    return DownloadHandle.failed(unsupportedMessage);
  }

  /// The stub backend has no way to open files — return `false` so the UI
  /// surfaces its existing "couldn't open" snackbar. The real Android
  /// backend overrides this with a MethodChannel call to the native plugin.
  @override
  Future<bool> openFile(String path) async => false;

  @override
  Future<bool> openFolder(String path) async => false;
}
