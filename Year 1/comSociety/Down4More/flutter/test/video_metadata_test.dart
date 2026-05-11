import 'package:down4more/models/video_metadata.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VideoMetadata.fromJson — fileSize population on quality ladder', () {
    test('rung at height h gets video size at <= h plus best audio', () {
      final json = {
        'title': 'T',
        'uploader': 'U',
        'duration': 60,
        'formats': <Map<String, dynamic>>[
          // 1080p video-only
          {
            'format_id': '137',
            'height': 1080,
            'filesize': 100_000,
            'vcodec': 'avc1',
            'acodec': 'none',
          },
          // 720p video-only
          {
            'format_id': '136',
            'height': 720,
            'filesize': 50_000,
            'vcodec': 'avc1',
            'acodec': 'none',
          },
          // best audio-only
          {
            'format_id': '140',
            'height': null,
            'filesize': 10_000,
            'vcodec': 'none',
            'acodec': 'mp4a',
          },
        ],
      };

      final m = VideoMetadata.fromJson('https://x', json);

      // Best should be 100k + 10k = 110k
      final best = m.formats.firstWhere((f) => f.label == 'Best available');
      expect(best.fileSize, 110_000);

      // 1080p rung should be 100k + 10k = 110k
      final r1080 = m.formats.firstWhere((f) => f.label == '1080p');
      expect(r1080.fileSize, 110_000);

      // 720p rung should be 50k + 10k = 60k (the 1080p video is excluded)
      final r720 = m.formats.firstWhere((f) => f.label == '720p');
      expect(r720.fileSize, 60_000);

      // Audio-only rung should be just the 10k audio
      final audio =
          m.formats.firstWhere((f) => f.label == 'Audio only');
      expect(audio.fileSize, 10_000);
    });

    test('handles formats without filesize gracefully (returns null)', () {
      final json = {
        'title': 'T',
        'uploader': 'U',
        'duration': 60,
        'formats': <Map<String, dynamic>>[
          {
            'format_id': '137',
            'height': 1080,
            'vcodec': 'avc1',
            'acodec': 'none',
            // no filesize fields
          },
        ],
      };
      final m = VideoMetadata.fromJson('https://x', json);
      final best = m.formats.firstWhere((f) => f.label == 'Best available');
      expect(best.fileSize, isNull);
    });

    test('falls back to filesize_approx when filesize is missing', () {
      final json = {
        'title': 'T',
        'uploader': 'U',
        'duration': 60,
        'formats': <Map<String, dynamic>>[
          {
            'format_id': '137',
            'height': 1080,
            'filesize_approx': 250_000,
            'vcodec': 'avc1',
            'acodec': 'none',
          },
          {
            'format_id': '140',
            'filesize_approx': 25_000,
            'vcodec': 'none',
            'acodec': 'mp4a',
          },
        ],
      };
      final m = VideoMetadata.fromJson('https://x', json);
      final best = m.formats.firstWhere((f) => f.label == 'Best available');
      expect(best.fileSize, 275_000);
    });
  });
}
