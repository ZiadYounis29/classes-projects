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

    return VideoMetadata(
      url: originalUrl,
      title: title,
      uploader: uploader,
      duration: duration,
      thumbnailUrl: thumbnailUrl,
      formats: formats,
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
  final videoSizesByHeight = <int, int>{};
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
    }
    // Muxed formats (both vcodec and acodec present) are skipped:
    // using them would double-count audio when we add bestAudioSize below.
  }

  // Fallback: if no video-only stream sizes were found (some platforms only
  // report sizes for muxed formats), collect muxed sizes instead. In that
  // case we do NOT add bestAudioSize on top — audio is already included.
  final bool useMuxedFallback = videoSizesByHeight.isEmpty;
  if (useMuxedFallback) {
    for (final f in rawFormats) {
      final h = (f['height'] as num?)?.round();
      final size = (f['filesize'] as num?) ?? (f['filesize_approx'] as num?);
      if (size == null || h == null) continue;
      final acodec = f['acodec'] as String? ?? 'none';
      final vcodec = f['vcodec'] as String? ?? 'none';
      if (vcodec != 'none' && acodec != 'none') {
        final bytes = size.round();
        final prev = videoSizesByHeight[h];
        if (prev == null || bytes > prev) videoSizesByHeight[h] = bytes;
      }
    }
  }

  final availableHeights = videoSizesByHeight.keys.toList()..sort();
  final hasAnyHeight = availableHeights.isNotEmpty;
  final topHeight = hasAnyHeight ? availableHeights.last : null;

  /// Best video size at or below [ceiling] plus audio (unless muxed fallback).
  /// Returns null when nothing is known so the UI hides the size chip.
  int? sizeForCeiling(int? ceiling) {
    int? video;
    for (final h in availableHeights) {
      if (ceiling != null && h > ceiling) continue;
      final s = videoSizesByHeight[h];
      if (s == null) continue;
      if (video == null || s > video) video = s;
    }
    if (video == null && bestAudioSize == null) return null;
    // When using muxed sizes the audio is already baked in — don't add it again.
    final audioAdd = useMuxedFallback ? 0 : (bestAudioSize ?? 0);
    return (video ?? 0) + audioAdd;
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
    final hasIt = availableHeights.any((avail) => avail >= h);
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
      label: 'Audio only (best)',
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
