import 'package:flutter/foundation.dart';

/// One playable variant of a video reported by `yt-dlp --dump-single-json`.
///
/// yt-dlp lists dozens of formats per video (separate audio + video streams,
/// muxed streams, every codec/bitrate combination). For Down4More's UI we only
/// surface a curated subset — the formats that are actually useful as
/// "qualities" the user might pick. See
/// `VideoMetadata._buildQualityList` for the curation.
@immutable
class VideoFormat {
  const VideoFormat({
    required this.id,
    required this.label,
    required this.ext,
    required this.height,
    required this.fileSize,
    required this.note,
    required this.isAudioOnly,
  });

  /// The yt-dlp `-f` value to pass to actually download this. May be a single
  /// numeric format id (e.g. `'137'`) or a selector expression
  /// (e.g. `'bv*[height<=1080]+ba/b[height<=1080]'`).
  final String id;

  /// User-facing label, e.g. `"1080p · MP4 · 124 MB"`.
  final String label;

  /// Container extension, e.g. `'mp4'`, `'webm'`, `'m4a'`.
  final String ext;

  /// Resolution height in pixels. `null` for audio-only formats.
  final int? height;

  /// File size in bytes if yt-dlp reported it. Often `null` for live streams or
  /// unmerged formats — UI must tolerate that.
  final int? fileSize;

  /// Optional yt-dlp `format_note` (e.g. `"DASH video"`, `"medium"`). Surface
  /// only if helpful; the label already covers most useful info.
  final String? note;

  final bool isAudioOnly;

  @override
  String toString() => 'VideoFormat(id=$id, label=$label)';
}

/// Everything Down4More's UI needs to know about a single video before
/// downloading it. Built from `yt-dlp --dump-single-json <url>`.
@immutable
class VideoMetadata {
  const VideoMetadata({
    required this.url,
    required this.title,
    required this.uploader,
    required this.duration,
    required this.thumbnailUrl,
    required this.formats,
    this.availableSubtitleLangs = const [],
    this.availableAutoCaptionLangs = const [],
  });

  /// The URL the user originally pasted (kept verbatim — yt-dlp may rewrite
  /// `webpage_url` to a canonical form, but we hand back what the user gave).
  final String url;

  final String title;

  /// Channel / uploader name. May be empty if yt-dlp couldn't resolve it.
  final String uploader;

  /// Run length. `null` for live streams / unknown.
  final Duration? duration;

  /// URL of a still thumbnail to render in the metadata card. `null` if none.
  final String? thumbnailUrl;

  /// Curated list of qualities the user can pick from. Always contains at
  /// least one entry: a `'best'` selector that lets yt-dlp pick.
  final List<VideoFormat> formats;

  /// Language codes for manually uploaded subtitles (from yt-dlp's
  /// `subtitles` field), e.g. `['en', 'ar', 'es']`. Empty when none available.
  final List<String> availableSubtitleLangs;

  /// Language codes for auto-generated / auto-translated captions (from
  /// yt-dlp's `automatic_captions` field). Empty when none available.
  final List<String> availableAutoCaptionLangs;

  /// Build from the JSON object returned by `yt-dlp --dump-single-json`.
  ///
  /// [originalUrl] is the URL the user pasted; we preserve it instead of using
  /// `json['webpage_url']` so the UI doesn't suddenly show a normalized form.
  factory VideoMetadata.fromJson(
    String originalUrl,
    Map<String, dynamic> json,
  ) {
    final title = (json['title'] as String?) ?? 'Unknown title';
    final uploader = (json['uploader'] as String?) ??
        (json['channel'] as String?) ??
        '';
    final durationSeconds = json['duration'] as num?;
    final duration = durationSeconds != null
        ? Duration(seconds: durationSeconds.round())
        : null;
    final thumbnailUrl = (json['thumbnail'] as String?) ??
        _pickBestThumbnail(json['thumbnails']);

    final rawFormats =
        (json['formats'] as List<dynamic>? ?? <dynamic>[]).cast<Map<String, dynamic>>();
    final formats = _buildQualityList(rawFormats);

    // Parse manually-uploaded subtitle language codes.
    final subtitlesMap = json['subtitles'] as Map<String, dynamic>?;
    final availableSubtitleLangs = subtitlesMap != null
        ? (subtitlesMap.keys.toList()..sort())
        : <String>[];

    // Parse auto-generated caption language codes. We only surface the
    // '*-orig' track — this is YouTube's raw speech-recognition caption in
    // the video's original spoken language (e.g. 'en-orig' for English,
    // 'ar-orig' for Arabic, 'es-orig' for Spanish). All other keys are
    // auto-translated variants which are not the original transcription.
    final autoCaptionsMap = json['automatic_captions'] as Map<String, dynamic>?;
    final availableAutoCaptionLangs = autoCaptionsMap != null
        ? (autoCaptionsMap.keys
            .where((k) => k.endsWith('-orig'))
            .toList()
              ..sort())
        : <String>[];

    return VideoMetadata(
      url: originalUrl,
      title: title,
      uploader: uploader,
      duration: duration,
      thumbnailUrl: thumbnailUrl,
      formats: formats,
      availableSubtitleLangs: availableSubtitleLangs,
      availableAutoCaptionLangs: availableAutoCaptionLangs,
    );
  }

  /// Picks a sensible default download choice: prefer the highest-resolution
  /// muxed format, fall back to "best" otherwise. Returns the first format if
  /// nothing else qualifies.
  VideoFormat get defaultFormat {
    if (formats.isEmpty) {
      throw StateError('VideoMetadata has no formats');
    }
    // Curated list always starts with the recommended/best entry.
    return formats.first;
  }

  /// The audio-only entry in the curated format list, if present.
  /// Its [VideoFormat.fileSize] is the real yt-dlp stream size for the best
  /// audio track — use this as [sourceAudioBytes] in [FormatDropdown] so
  /// audio format rows always display the accurate size regardless of which
  /// video quality is currently selected.
  VideoFormat? get audioOnlyFormat =>
      formats.where((f) => f.isAudioOnly).firstOrNull;
}

/// Curate yt-dlp's format list down to the entries that are useful as a
/// "pick a quality" dropdown. We:
/// 1. Always prepend a `bv*+ba/b` "best" selector so the user can just click
///    download without thinking.
/// 2. Add one entry per common ladder rung (2160, 1440, 1080, 720, 480, 360,
///    240) using a height-bounded selector — that way yt-dlp can pick the
///    best codec/container at that ceiling instead of us hard-coding ids.
/// 3. Add an audio-only "best audio" entry.
///
/// For each entry we also compute an expected file size by walking the raw
/// format list: per height, the largest reported `filesize` (or
/// `filesize_approx`) is used as the representative video size; the best
/// audio-only format's size is added on top. The result is shown next to
/// the quality label so the user can compare disk cost at a glance.
///
/// We deliberately do NOT just expose every raw yt-dlp format id — most of
/// them are partial streams (video-only or audio-only) and downloading them
/// would produce a broken file unless merged with another. The selector
/// expressions above let yt-dlp do the merge automatically.
List<VideoFormat> _buildQualityList(List<Map<String, dynamic>> rawFormats) {
  // height → biggest-known filesize at that height. Many videos report a
  // filesize for some formats and not others; we take the max so the rung
  // size reflects the highest-quality variant the user could actually pick.
  final videoSizesByHeight = <int, int>{};  // video-only streams
  final muxedSizesByHeight = <int, int>{};  // muxed (audio+video) streams
  int? bestAudioSize;

  for (final f in rawFormats) {
    final h = (f['height'] as num?)?.round();
    final size = (f['filesize'] as num?) ?? (f['filesize_approx'] as num?);
    if (size == null) continue;
    final bytes = size.round();
    final acodec = f['acodec'] as String? ?? 'none';
    final vcodec = f['vcodec'] as String? ?? 'none';
    if (h != null && vcodec != 'none' && acodec == 'none') {
      // Video-only stream — safe to add audio size on top later.
      final prev = videoSizesByHeight[h];
      if (prev == null || bytes > prev) videoSizesByHeight[h] = bytes;
    } else if (vcodec == 'none' && acodec != 'none') {
      // Audio-only format. yt-dlp marks vcodec='none' for these.
      if (bestAudioSize == null || bytes > bestAudioSize) {
        bestAudioSize = bytes;
      }
    } else if (h != null && vcodec != 'none' && acodec != 'none') {
      // Muxed stream — collect separately so we can use it as a per-rung
      // fallback when no video-only stream exists at that height (e.g. 240p
      // and 144p on YouTube which only ship as muxed).
      final prev = muxedSizesByHeight[h];
      if (prev == null || bytes > prev) muxedSizesByHeight[h] = bytes;
    }
  }

  // If absolutely no video-only streams were found (some platforms never
  // separate streams), promote all muxed sizes into the primary map so the
  // logic below has something to work with. In this mode we skip adding
  // bestAudioSize because audio is already baked into the muxed size.
  final bool allMuxed = videoSizesByHeight.isEmpty;
  if (allMuxed) {
    muxedSizesByHeight.forEach((h, s) => videoSizesByHeight[h] = s);
  }

  final availableHeights = videoSizesByHeight.keys.toList()..sort();
  // Heights that have muxed data but no video-only data — used as a
  // per-rung fallback inside sizeForCeiling.
  final muxedOnlyHeights = muxedSizesByHeight.keys
      .where((h) => !videoSizesByHeight.containsKey(h))
      .toList()
        ..sort();
  final allKnownHeights = {
    ...availableHeights,
    ...muxedOnlyHeights,
  }.toList()..sort();

  final hasAnyHeight = allKnownHeights.isNotEmpty;
  final topHeight = hasAnyHeight ? allKnownHeights.last : null;

  /// Best estimated size for a download capped at [ceiling] pixels tall.
  ///
  /// Priority:
  ///   1. Largest video-only stream at or below ceiling + bestAudioSize.
  ///   2. If no video-only stream exists at or below ceiling, use the largest
  ///      muxed stream at or below ceiling (audio already included).
  ///   3. Return null when no size data is available at all.
  int? sizeForCeiling(int? ceiling) {
    // ── Pass 1: video-only streams ──────────────────────────────────────
    int? video;
    for (final h in availableHeights) {
      if (ceiling != null && h > ceiling) continue;
      final s = videoSizesByHeight[h];
      if (s == null) continue;
      if (video == null || s > video) video = s;
    }
    if (video != null) {
      // When the primary map was built from muxed data (allMuxed), audio is
      // already included — do not add bestAudioSize again.
      final audioAdd = allMuxed ? 0 : (bestAudioSize ?? 0);
      return video + audioAdd;
    }

    // ── Pass 2: muxed-only fallback (e.g. 240p / 144p on YouTube) ──────
    int? muxed;
    for (final h in muxedOnlyHeights) {
      if (ceiling != null && h > ceiling) continue;
      final s = muxedSizesByHeight[h];
      if (s == null) continue;
      if (muxed == null || s > muxed) muxed = s;
    }
    if (muxed != null) return muxed; // audio already included in muxed size

    // ── Pass 3: audio only (no video size known at all) ─────────────────
    if (bestAudioSize != null) return bestAudioSize;
    return null;
  }

  final out = <VideoFormat>[
    VideoFormat(
      id: 'bv*+ba/b',
      label: 'Best available',
      ext: 'mp4',
      height: null,
      fileSize: sizeForCeiling(topHeight),
      note: 'Highest quality video + audio',
      isAudioOnly: false,
    ),
  ];

  // Common resolution rungs. Only show ones the source actually has.
  const ladder = <int>[2160, 1440, 1080, 720, 480, 360, 240, 144];
  for (final h in ladder) {
    final hasIt = allKnownHeights.any((avail) => avail >= h);
    if (!hasIt) continue;
    // For each rung, ask yt-dlp to mux best video <= h with best audio.
    out.add(
      VideoFormat(
        id: 'bv*[height<=$h]+ba/b[height<=$h]',
        label: '${h}p',
        ext: 'mp4',
        height: h,
        fileSize: sizeForCeiling(h),
        note: null,
        isAudioOnly: false,
      ),
    );
  }

  out.add(
    VideoFormat(
      id: 'ba/b',
      label: 'Audio only',
      ext: 'm4a',
      height: null,
      fileSize: bestAudioSize,
      note: 'Audio-only — handy for music',
      isAudioOnly: true,
    ),
  );

  return out;
}

String? _pickBestThumbnail(dynamic thumbnails) {
  if (thumbnails is! List) return null;
  Map<String, dynamic>? best;
  int bestArea = 0;
  for (final t in thumbnails) {
    if (t is! Map) continue;
    final m = t.cast<String, dynamic>();
    final w = (m['width'] as num?)?.round() ?? 0;
    final h = (m['height'] as num?)?.round() ?? 0;
    final area = w * h;
    if (area > bestArea) {
      best = m;
      bestArea = area;
    }
  }
  return best?['url'] as String?;
}
