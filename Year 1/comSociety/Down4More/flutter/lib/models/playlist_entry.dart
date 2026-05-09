import 'package:flutter/foundation.dart';

/// A single video entry inside a playlist, fetched via
/// `yt-dlp --flat-playlist --dump-json`.
///
/// This is a lightweight "preview" — it has no format list or quality
/// information yet. Full metadata is fetched per-video at download time.
@immutable
class PlaylistEntry {
  const PlaylistEntry({
    required this.id,
    required this.title,
    required this.url,
    this.duration,
    this.thumbnailUrl,
    this.uploader,
  });

  final String id;
  final String title;
  final String url;
  final Duration? duration;
  final String? thumbnailUrl;
  final String? uploader;

  factory PlaylistEntry.fromJson(Map<String, dynamic> json) {
    var url = (json['url'] as String?) ??
        (json['webpage_url'] as String?) ??
        '';
    if (url.isNotEmpty && !url.startsWith('http')) {
      url = 'https://www.youtube.com/watch?v=$url';
    }

    final durationSec = json['duration'] as num?;

    final thumbnails = json['thumbnails'];
    String? thumb = json['thumbnail'] as String?;
    if (thumb == null && thumbnails is List && thumbnails.isNotEmpty) {
      final last = thumbnails.last;
      if (last is Map) thumb = last['url'] as String?;
    }

    return PlaylistEntry(
      id: (json['id'] as String?) ?? '',
      title: (json['title'] as String?) ?? 'Unknown',
      url: url,
      duration: durationSec != null
          ? Duration(seconds: durationSec.round())
          : null,
      thumbnailUrl: thumb,
      uploader: (json['uploader'] as String?) ??
          (json['channel'] as String?),
    );
  }
}
