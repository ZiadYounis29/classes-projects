import 'package:down4more/models/output_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('OutputFormat.estimateBytes (video)', () {
    test('mp4 preserves source size 1:1', () {
      final mp4 = kVideoFormats.firstWhere((f) => f.ext == 'mp4');
      expect(
        mp4.estimateBytes(sourceVideoBytes: 1_000_000, duration: null),
        1_000_000,
      );
    });

    test('webm scales source size by 0.95', () {
      final webm = kVideoFormats.firstWhere((f) => f.ext == 'webm');
      expect(
        webm.estimateBytes(sourceVideoBytes: 1_000_000, duration: null),
        950_000,
      );
    });

    test('returns null when source video bytes unknown', () {
      final mp4 = kVideoFormats.firstWhere((f) => f.ext == 'mp4');
      expect(
        mp4.estimateBytes(sourceVideoBytes: null, duration: null),
        isNull,
      );
    });
  });

  group('OutputFormat.estimateBytes (audio)', () {
    test('mp3 at 128 kbps for 60s ≈ 960_000 bytes', () {
      final mp3 = kAudioFormats.firstWhere((f) => f.ext == 'mp3');
      // 128 kbps * 1000 * 60 / 8 = 960,000
      expect(
        mp3.estimateBytes(
            sourceVideoBytes: 1_000_000, duration: const Duration(seconds: 60)),
        960_000,
      );
    });

    test('flac at 700 kbps for 60s ≈ 5_250_000 bytes', () {
      final flac = kAudioFormats.firstWhere((f) => f.ext == 'flac');
      expect(
        flac.estimateBytes(
            sourceVideoBytes: null, duration: const Duration(seconds: 60)),
        5_250_000,
      );
    });

    test('audio formats need a duration to estimate', () {
      final mp3 = kAudioFormats.firstWhere((f) => f.ext == 'mp3');
      expect(
        mp3.estimateBytes(sourceVideoBytes: 1_000_000, duration: null),
        isNull,
      );
    });
  });
}
