import 'package:flutter/foundation.dart';

/// The phases a single download can be in. Used by both the controller's
/// state machine and the UI's switch on what to render.
enum DownloadPhase {
  /// Empty input. UI shows the "paste a URL" prompt.
  idle,

  /// `yt-dlp --dump-single-json` is running. UI shows a spinner.
  fetchingMetadata,

  /// Metadata returned successfully. UI shows the metadata card + quality
  /// dropdown + a "Download" button.
  ready,

  /// `yt-dlp` is downloading the chosen format. UI shows a progress bar.
  downloading,

  /// File saved to disk successfully. UI shows the success card with
  /// "Open file" / "Open folder" actions.
  finished,

  /// Either fetch or download failed. UI shows the error and a retry button.
  error,

  /// User clicked Cancel; subprocess was killed. UI offers to try again.
  cancelled,
}

/// A snapshot of a single download's progress. The controller emits one of
/// these every time the underlying yt-dlp process reports a new line of
/// stdout, plus on phase transitions.
@immutable
class DownloadProgress {
  const DownloadProgress({
    required this.phase,
    this.percent,
    this.speedBytesPerSecond,
    this.eta,
    this.totalBytes,
    this.bytesDownloaded,
    this.message,
    this.errorMessage,
    this.outputPath,
  });

  final DownloadPhase phase;

  /// 0.0–100.0 progress percentage. `null` when not in [DownloadPhase.downloading].
  final double? percent;

  final double? speedBytesPerSecond;

  /// Estimated remaining time. yt-dlp reports it as `MM:SS` or `HH:MM:SS`.
  final Duration? eta;

  final int? totalBytes;
  final int? bytesDownloaded;

  /// Free-form status line from yt-dlp ("Destination: ...", "Merging formats",
  /// etc.). Shown under the progress bar.
  final String? message;

  /// Populated on [DownloadPhase.error]. Always show this verbatim — yt-dlp's
  /// own error wording is more useful than anything we'd paraphrase.
  final String? errorMessage;

  /// Populated on [DownloadPhase.finished] (and earlier when yt-dlp prints
  /// `Destination: ...`). Absolute path on disk.
  final String? outputPath;

  /// Convenience constructor for the common "we just changed phase" case.
  static const DownloadProgress idle =
      DownloadProgress(phase: DownloadPhase.idle);
}
