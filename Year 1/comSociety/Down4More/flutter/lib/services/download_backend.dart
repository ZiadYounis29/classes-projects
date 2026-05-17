import '../models/playlist_entry.dart';
import '../models/subtitle_settings.dart';
import '../models/video_metadata.dart';
import 'ytdlp_service.dart' show DownloadHandle;

// Re-export the bits of ytdlp_service.dart that any consumer of this
// interface is likely to need (the handle type returned by [download] and
// the exception type thrown by metadata / playlist fetches). Lets
// controllers depend only on download_backend.dart and stay agnostic of the
// concrete backend they were handed.
export 'ytdlp_service.dart' show DownloadHandle, YtDlpException;

/// Cross-platform interface for "thing that downloads videos and tells the
/// UI how it's going."
///
/// Today this is implemented exactly once \u2014 [YtDlpService] for desktop
/// (Linux / macOS / Windows). The point of pulling it out as an interface
/// now is that Android needs a completely different implementation: yt-dlp
/// and ffmpeg are CLI binaries that don't run on Android, and Android
/// apps can't spawn arbitrary subprocesses anyway. The Android port will
/// land later as an `AndroidYtDlpBackend` that wraps the youtubedl-android
/// JVM library over a `MethodChannel`.
///
/// Until that's wired up, [AndroidBackendStub] is what controllers get on
/// Android \u2014 every method throws a descriptive [UnsupportedError] (or, for
/// [download], emits a single error event so the UI's existing error-card
/// path is used instead of an uncaught exception).
///
/// Controllers depend on this interface, never on [YtDlpService] directly,
/// so swapping backends per-platform is a single conditional in the
/// `createDefaultBackend()` factory in `download_backend_factory.dart`.
abstract class DownloadBackend {
  /// One-shot metadata fetch for a single URL. See
  /// [YtDlpService.fetchMetadata] for the contract.
  Future<VideoMetadata> fetchMetadata(String url);

  /// One-shot playlist enumeration. See [YtDlpService.fetchPlaylist].
  Future<List<PlaylistEntry>> fetchPlaylist(String url);

  /// Best-effort playlist title. Returns null (not throw) when the backend
  /// can't determine one. See [YtDlpService.getPlaylistTitle].
  Future<String?> getPlaylistTitle(String url);

  /// Kick off an actual download. Returns a [DownloadHandle] that streams
  /// progress events and supports pause / resume / cancel. See
  /// [YtDlpService.download] for the full argument contract.
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
  });

  /// Open the file at [path] in the platform's default viewer. Returns
  /// `true` on success, `false` otherwise (so callers can show a "couldn't
  /// open" hint without needing to special-case exceptions).
  ///
  /// On desktop this delegates to `url_launcher` against a `Uri.file(path)`.
  /// On Android the URL launcher can't open arbitrary `file://` URIs since
  /// API 24, so the native plugin resolves a MediaStore content URI for
  /// files under `Movies/Down4More/...` and hands that to `ACTION_VIEW`.
  Future<bool> openFile(String path);

  /// Reveal the file at [path] inside its containing folder using the
  /// platform's file manager. Returns `true` on success.
  ///
  /// On desktop this is a `launchUrl(Uri.file(parentDir))`. On Android the
  /// native plugin opens the Files app filtered to the parent collection
  /// (`Movies/Down4More` for video, `Music/Down4More` for audio) so the
  /// user lands somewhere they can actually navigate from.
  Future<bool> openFolder(String path);
}
