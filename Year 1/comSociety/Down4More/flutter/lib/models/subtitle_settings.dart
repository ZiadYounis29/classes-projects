import 'package:flutter/foundation.dart';

import 'output_format.dart';

/// User-facing description of a subtitle language. The [code] is what gets
/// passed to yt-dlp via `--sub-langs`. The [label] is shown in dropdowns.
@immutable
class SubtitleLanguage {
  const SubtitleLanguage({required this.code, required this.label});

  final String code;
  final String label;

  @override
  bool operator ==(Object other) =>
      other is SubtitleLanguage && other.code == code;

  @override
  int get hashCode => code.hashCode;
}

/// Twelve common subtitle languages presented in the dropdown. Other
/// languages are typed in via the "Other…" text input. The order roughly
/// follows YouTube global usage with English first.
const List<SubtitleLanguage> kSubtitleLanguages = [
  SubtitleLanguage(code: 'en', label: 'English (en)'),
  SubtitleLanguage(code: 'ar', label: 'Arabic (ar)'),
  SubtitleLanguage(code: 'es', label: 'Spanish (es)'),
  SubtitleLanguage(code: 'fr', label: 'French (fr)'),
  SubtitleLanguage(code: 'de', label: 'German (de)'),
  SubtitleLanguage(code: 'it', label: 'Italian (it)'),
  SubtitleLanguage(code: 'pt', label: 'Portuguese (pt)'),
  SubtitleLanguage(code: 'ru', label: 'Russian (ru)'),
  SubtitleLanguage(code: 'ja', label: 'Japanese (ja)'),
  SubtitleLanguage(code: 'ko', label: 'Korean (ko)'),
  SubtitleLanguage(code: 'zh', label: 'Chinese (zh)'),
  SubtitleLanguage(code: 'hi', label: 'Hindi (hi)'),
  SubtitleLanguage(code: 'tr', label: 'Turkish (tr)'),
];

/// Subtitle file formats yt-dlp can produce via `--sub-format` / `--convert-subs`.
@immutable
class SubtitleFormat {
  const SubtitleFormat({required this.ext, required this.label});

  final String ext;
  final String label;

  @override
  bool operator ==(Object other) =>
      other is SubtitleFormat && other.ext == ext;

  @override
  int get hashCode => ext.hashCode;
}

/// Common subtitle output formats. SRT is the universal default.
const List<SubtitleFormat> kSubtitleFormats = [
  SubtitleFormat(ext: 'srt', label: 'SRT — SubRip (universal)'),
  SubtitleFormat(ext: 'vtt', label: 'VTT — WebVTT (HTML5)'),
  SubtitleFormat(ext: 'ass', label: 'ASS — Advanced styled'),
  SubtitleFormat(ext: 'lrc', label: 'LRC — Lyric / karaoke'),
];

const SubtitleFormat kDefaultSubtitleFormat = SubtitleFormat(
  ext: 'srt',
  label: 'SRT — SubRip (universal)',
);

/// Output containers that yt-dlp can mux subtitles directly into via
/// `--embed-subs`. WebM technically only supports WebVTT, MP3 / M4A and
/// the rest can't carry video subtitle tracks at all — so we only allow
/// embedding into MP4 and MKV.
const Set<String> kEmbedSubsSupportedExts = {'mp4', 'mkv'};

/// Whether [format] supports embedding subtitles via `--embed-subs`.
/// The single source of truth used by both the SubtitleInput widget (to
/// gate the toggle) and the controllers (to auto-snap the toggle off when
/// the user switches to a non-embeddable format).
bool outputFormatSupportsEmbed(OutputFormat format) =>
    kEmbedSubsSupportedExts.contains(format.ext);

/// Per-download subtitle configuration.
///
/// All fields are optional so the [disabled] default represents "don't
/// download subtitles at all" — equivalent to passing no `--write-subs`
/// flag to yt-dlp. The various screens build a non-default value via
/// [copyWith] / the named constructors and pass it down to the
/// controllers, which forward it to [YtDlpService.download].
@immutable
class SubtitleSettings {
  const SubtitleSettings({
    this.enabled = false,
    this.language = 'en',
    this.format = 'srt',
    this.embed = false,
    this.useAutoCaption = false,
  });

  /// Master switch. When false the queue / single screen pretends this
  /// settings object doesn't exist — yt-dlp gets no subtitle flags at all.
  final bool enabled;

  /// IETF language tag (e.g. `en`, `ar`, `pt-BR`). Passed verbatim to
  /// `--sub-langs`. Free-form so users can type uncommon ones via the
  /// "Other…" field.
  final String language;

  /// Subtitle file format extension. yt-dlp maps these via `--sub-format` /
  /// `--convert-subs`. The most-compatible default is `srt`.
  final String format;

  /// Whether to mux subtitles directly into the video container (only
  /// supported when the chosen output format is in
  /// [kEmbedSubsSupportedExts]). When false, subtitles are written as a
  /// separate sidecar file next to the video.
  final bool embed;

  /// When true, the selected [language] is an auto-caption track (from
  /// yt-dlp's `automatic_captions` field) rather than a manually-uploaded
  /// subtitle. The download service uses `--write-auto-subs` exclusively
  /// (no `--write-subs`) and passes the lang code via `--sub-langs`.
  final bool useAutoCaption;

  static const SubtitleSettings disabled = SubtitleSettings();

  SubtitleSettings copyWith({
    bool? enabled,
    String? language,
    String? format,
    bool? embed,
    bool? useAutoCaption,
  }) {
    return SubtitleSettings(
      enabled: enabled ?? this.enabled,
      language: language ?? this.language,
      format: format ?? this.format,
      embed: embed ?? this.embed,
      useAutoCaption: useAutoCaption ?? this.useAutoCaption,
    );
  }

  /// Snap [embed] to false when [outputFormat] doesn't support it. Used by
  /// the controllers when the user switches output formats while subtitles
  /// are configured.
  SubtitleSettings snapEmbedFor(OutputFormat outputFormat) {
    if (embed && !outputFormatSupportsEmbed(outputFormat)) {
      return copyWith(embed: false);
    }
    return this;
  }

  @override
  bool operator ==(Object other) =>
      other is SubtitleSettings &&
      other.enabled == enabled &&
      other.language == language &&
      other.format == format &&
      other.embed == embed &&
      other.useAutoCaption == useAutoCaption;

  @override
  int get hashCode =>
      Object.hash(enabled, language, format, embed, useAutoCaption);

  @override
  String toString() =>
      'SubtitleSettings(enabled: $enabled, language: $language, '
      'format: $format, embed: $embed, '
      'useAutoCaption: $useAutoCaption)';
}
