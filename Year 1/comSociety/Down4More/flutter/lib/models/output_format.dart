import 'package:flutter/foundation.dart';

/// Whether a format produces a video file or an audio-only file.
/// Used to decide which yt-dlp flags to pass and which formats to show.
enum OutputCategory { video, audio }

/// A concrete output container/codec the user can request.
///
/// Video formats use `--merge-output-format <ext>`.
/// Audio formats use `-x --audio-format <ext>`.
@immutable
class OutputFormat {
  const OutputFormat({
    required this.ext,
    required this.label,
    required this.category,
    this.note,
    this.videoSizeMultiplier,
    this.audioBitrateKbps,
  });

  /// File extension / yt-dlp format name, e.g. `'mp4'`, `'mp3'`.
  final String ext;

  /// User-facing name shown in the dropdown, e.g. `'MP4'`, `'MP3'`.
  final String label;

  final OutputCategory category;

  /// Optional one-liner shown as a subtitle, e.g. `'Best compatibility'`.
  final String? note;

  /// For video formats: rough estimate of output size as a fraction of the
  /// source video's file size. MP4 / MKV are direct remuxes (~1.00×), WebM
  /// is a slightly smaller container (~0.95×). `null` for audio formats.
  final double? videoSizeMultiplier;

  /// For audio formats: the typical encoder bitrate in kilobits per second,
  /// used to estimate output size as `duration × kbps × 1000 / 8`. FLAC and
  /// WAV use representative values for CD-quality stereo. `null` for video.
  final int? audioBitrateKbps;

  bool get isAudio => category == OutputCategory.audio;
  bool get isVideo => category == OutputCategory.video;

  /// Estimate the output file size in bytes given the source video's size and
  /// duration. Returns `null` when the inputs aren't sufficient (e.g. no
  /// source size for a video format, or no duration for an audio format).
  ///
  /// `sourceVideoBytes` is the curated `VideoFormat.fileSize` of the
  /// currently-selected quality. `duration` is `VideoMetadata.duration`.
  int? estimateBytes({
    int? sourceVideoBytes,
    int? sourceAudioBytes,
    Duration? duration,
  }) {
    if (isVideo) {
      if (sourceVideoBytes == null || videoSizeMultiplier == null) return null;
      return (sourceVideoBytes * videoSizeMultiplier!).round();
    }
    // Audio: M4A is a direct remux of the AAC stream yt-dlp downloads — no
    // re-encoding happens, so the output file size equals the raw stream size
    // that yt-dlp reported. Use sourceAudioBytes directly for M4A when available.
    // All other audio formats (MP3, FLAC, WAV, Opus, OGG) are transcodes whose
    // output size depends on the encoder bitrate, not the source stream size,
    // so they keep using the bitrate x duration formula.
    if (ext == 'm4a' && sourceAudioBytes != null) return sourceAudioBytes;
    if (duration == null || audioBitrateKbps == null) return null;
    return (audioBitrateKbps! * 1000 * duration.inSeconds / 8).round();
  }

  @override
  String toString() => 'OutputFormat($ext)';

  @override
  bool operator ==(Object other) =>
      other is OutputFormat && other.ext == ext;

  @override
  int get hashCode => ext.hashCode;
}

// ── Canonical lists ──────────────────────────────────────────────────────────

/// All video containers Down4More supports.
const List<OutputFormat> kVideoFormats = [
  OutputFormat(
    ext: 'mp4',
    label: 'MP4',
    category: OutputCategory.video,
    note: 'Best compatibility',
    videoSizeMultiplier: 1.0,
  ),
  OutputFormat(
    ext: 'mkv',
    label: 'MKV',
    category: OutputCategory.video,
    note: 'Keeps all streams, larger file',
    videoSizeMultiplier: 1.0,
  ),
  OutputFormat(
    ext: 'webm',
    label: 'WebM',
    category: OutputCategory.video,
    note: 'Open format, VP9/Opus',
    videoSizeMultiplier: 0.95,
  ),
];

/// All audio formats Down4More supports. 'ogg' is passed to yt-dlp as
/// 'vorbis' (see [YtDlpService]), but we expose the familiar extension.
const List<OutputFormat> kAudioFormats = [
  OutputFormat(
    ext: 'm4a',
    label: 'M4A',
    category: OutputCategory.audio,
    note: 'AAC in MPEG-4 container',
    audioBitrateKbps: 128,
  ),
  OutputFormat(
    ext: 'mp3',
    label: 'MP3',
    category: OutputCategory.audio,
    note: 'Universal compatibility',
    audioBitrateKbps: 128,
  ),
  OutputFormat(
    ext: 'opus',
    label: 'Opus',
    category: OutputCategory.audio,
    note: 'Best quality per bit',
    audioBitrateKbps: 96,
  ),
  OutputFormat(
    ext: 'flac',
    label: 'FLAC',
    category: OutputCategory.audio,
    note: 'Lossless',
    // Roughly half of WAV PCM thanks to lossless compression on stereo audio.
    audioBitrateKbps: 700,
  ),
  OutputFormat(
    ext: 'wav',
    label: 'WAV',
    category: OutputCategory.audio,
    note: 'Uncompressed PCM',
    // 16-bit / 44.1 kHz / stereo — the canonical CD-audio bitrate.
    audioBitrateKbps: 1411,
  ),
  OutputFormat(
    ext: 'ogg',
    label: 'OGG',
    category: OutputCategory.audio,
    note: 'Vorbis in Ogg container',
    audioBitrateKbps: 96,
  ),
];

/// Default video format.
const OutputFormat kDefaultVideoFormat = OutputFormat(
  ext: 'mp4',
  label: 'MP4',
  category: OutputCategory.video,
  note: 'Best compatibility',
  videoSizeMultiplier: 1.0,
);

/// Default audio format (used when the quality selection is audio-only).
const OutputFormat kDefaultAudioFormat = OutputFormat(
  ext: 'm4a',
  label: 'M4A',
  category: OutputCategory.audio,
  note: 'AAC in MPEG-4 container',
  audioBitrateKbps: 128,
);
