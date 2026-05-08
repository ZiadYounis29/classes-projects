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
  });

  /// File extension / yt-dlp format name, e.g. `'mp4'`, `'mp3'`.
  final String ext;

  /// User-facing name shown in the dropdown, e.g. `'MP4'`, `'MP3'`.
  final String label;

  final OutputCategory category;

  /// Optional one-liner shown as a subtitle, e.g. `'Best compatibility'`.
  final String? note;

  bool get isAudio => category == OutputCategory.audio;
  bool get isVideo => category == OutputCategory.video;

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
  ),
  OutputFormat(
    ext: 'mkv',
    label: 'MKV',
    category: OutputCategory.video,
    note: 'Keeps all streams, larger file',
  ),
  OutputFormat(
    ext: 'webm',
    label: 'WebM',
    category: OutputCategory.video,
    note: 'Open format, VP9/Opus',
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
  ),
  OutputFormat(
    ext: 'mp3',
    label: 'MP3',
    category: OutputCategory.audio,
    note: 'Universal compatibility',
  ),
  OutputFormat(
    ext: 'opus',
    label: 'Opus',
    category: OutputCategory.audio,
    note: 'Best quality per bit',
  ),
  OutputFormat(
    ext: 'flac',
    label: 'FLAC',
    category: OutputCategory.audio,
    note: 'Lossless',
  ),
  OutputFormat(
    ext: 'wav',
    label: 'WAV',
    category: OutputCategory.audio,
    note: 'Uncompressed PCM',
  ),
  OutputFormat(
    ext: 'ogg',
    label: 'OGG',
    category: OutputCategory.audio,
    note: 'Vorbis in Ogg container',
  ),
];

/// Default video format.
const OutputFormat kDefaultVideoFormat = OutputFormat(
  ext: 'mp4',
  label: 'MP4',
  category: OutputCategory.video,
  note: 'Best compatibility',
);

/// Default audio format (used when the quality selection is audio-only).
const OutputFormat kDefaultAudioFormat = OutputFormat(
  ext: 'm4a',
  label: 'M4A',
  category: OutputCategory.audio,
  note: 'AAC in MPEG-4 container',
);
