import 'dart:convert';
import 'dart:io';

import 'package:down4more/models/download_progress.dart';
import 'package:down4more/services/ytdlp_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseProgressLine', () {
    test('parses a typical [download] line with percent + size + speed + ETA',
        () {
      final p = parseProgressLine(
        '[download]   1.5% of  100.00MiB at  2.50MiB/s ETA 00:39',
      );
      expect(p, isNotNull);
      expect(p!.phase, DownloadPhase.downloading);
      expect(p.percent, closeTo(1.5, 0.001));
      expect(p.totalBytes, closeTo(100 * 1024 * 1024, 1));
      expect(p.speedBytesPerSecond, closeTo(2.5 * 1024 * 1024, 1));
      expect(p.eta, equals(const Duration(minutes: 0, seconds: 39)));
    });

    test('handles "in 00:08 at 2.84MiB/s" terminal line', () {
      final p = parseProgressLine(
        '[download] 100% of   23.86MiB in 00:08 at 2.84MiB/s',
      );
      expect(p, isNotNull);
      expect(p!.percent, closeTo(100.0, 0.001));
      // No "ETA" group → eta should be null. Speed/total are still useful.
      expect(p.eta, isNull);
    });

    test('parses a [download] Destination: line into outputPath', () {
      final p = parseProgressLine(
        '[download] Destination: /tmp/Down4More/foo.mp4',
      );
      expect(p, isNotNull);
      expect(p!.outputPath, equals('/tmp/Down4More/foo.mp4'));
      expect(p.phase, DownloadPhase.downloading);
    });

    test('parses [Merger] Merging formats lines', () {
      final p = parseProgressLine(
        '[Merger] Merging formats into "/tmp/Down4More/foo.mp4"',
      );
      expect(p, isNotNull);
      expect(p!.outputPath, equals('/tmp/Down4More/foo.mp4'));
      expect(p.percent, equals(100));
    });

    test('returns null for unrelated lines', () {
      expect(parseProgressLine(''), isNull);
      expect(parseProgressLine('[info] Whatever'), isNull);
      expect(parseProgressLine('Something completely random'), isNull);
    });

    test('tolerates ~ approximate-size prefix', () {
      final p = parseProgressLine(
        '[download]  50.0% of ~  10.00MiB at  1.00MiB/s ETA 00:05',
      );
      expect(p, isNotNull);
      expect(p!.percent, closeTo(50.0, 0.001));
    });
  });

  group('YtDlpService.fetchMetadata', () {
    test('parses yt-dlp JSON output into a VideoMetadata', () async {
      final fakeJson = jsonEncode({
        'title': 'Test video',
        'uploader': 'TestChannel',
        'duration': 95,
        'thumbnail': 'https://example.com/t.jpg',
        'formats': <Map<String, dynamic>>[
          {'format_id': '137', 'height': 1080, 'filesize': 50 * 1024 * 1024},
          {'format_id': '136', 'height': 720, 'filesize': 25 * 1024 * 1024},
          {'format_id': '140', 'acodec': 'mp4a.40.2', 'filesize': 5 * 1024 * 1024},
        ],
      });
      final svc = YtDlpService(
        executable: 'fake-yt-dlp',
        processRunner: (exe, args) async => ProcessResult(0, 0, fakeJson, ''),
      );
      final m = await svc.fetchMetadata('https://example.com/v');
      expect(m.title, 'Test video');
      expect(m.uploader, 'TestChannel');
      expect(m.duration, equals(const Duration(seconds: 95)));
      // Curated format list always starts with "Best available".
      expect(m.formats.first.label, 'Best available');
      // Should include 1080p and 720p rungs since the source has them.
      expect(m.formats.where((f) => f.height == 1080).length, 1);
      expect(m.formats.where((f) => f.height == 720).length, 1);
      // Should include audio-only as last entry.
      expect(m.formats.last.isAudioOnly, isTrue);
    });

    test('throws YtDlpException with stderr on non-zero exit', () async {
      final svc = YtDlpService(
        executable: 'fake-yt-dlp',
        processRunner: (exe, args) async =>
            ProcessResult(0, 1, '', 'ERROR: Unsupported URL'),
      );
      expect(
        () => svc.fetchMetadata('https://nope'),
        throwsA(
          isA<YtDlpException>().having(
            (e) => e.message,
            'message',
            contains('Unsupported URL'),
          ),
        ),
      );
    });

    test('throws YtDlpException when binary is missing', () async {
      final svc = YtDlpService(
        executable: 'fake-yt-dlp',
        processRunner: (exe, args) async =>
            throw const ProcessException('fake-yt-dlp', []),
      );
      expect(
        () => svc.fetchMetadata('https://example.com/v'),
        throwsA(isA<YtDlpException>()),
      );
    });

    test('throws on empty URL without spawning a process', () async {
      var spawned = 0;
      final svc = YtDlpService(
        executable: 'fake-yt-dlp',
        processRunner: (_, __) async {
          spawned++;
          return ProcessResult(0, 0, '{}', '');
        },
      );
      await expectLater(
        () => svc.fetchMetadata('   '),
        throwsA(isA<YtDlpException>()),
      );
      expect(spawned, 0);
    });
  });

  group('YtDlpService.getPlaylistTitle', () {
    test('returns the first non-empty stdout line', () async {
      final svc = YtDlpService(
        executable: 'fake-yt-dlp',
        processRunner: (exe, args) async =>
            ProcessResult(0, 0, 'Lo-fi study mix\n', ''),
      );
      final title = await svc.getPlaylistTitle('https://example.com/p');
      expect(title, 'Lo-fi study mix');
    });

    test('returns null when yt-dlp prints empty / NA', () async {
      final svc = YtDlpService(
        executable: 'fake-yt-dlp',
        processRunner: (exe, args) async =>
            ProcessResult(0, 0, '\nNA\n   \n', ''),
      );
      expect(await svc.getPlaylistTitle('https://x'), isNull);
    });

    test('returns null on empty input without spawning', () async {
      var spawned = 0;
      final svc = YtDlpService(
        executable: 'fake-yt-dlp',
        processRunner: (_, __) async {
          spawned++;
          return ProcessResult(0, 0, 'X', '');
        },
      );
      expect(await svc.getPlaylistTitle('   '), isNull);
      expect(spawned, 0);
    });

    test('returns null instead of throwing on yt-dlp failure', () async {
      final svc = YtDlpService(
        executable: 'fake-yt-dlp',
        processRunner: (exe, args) async =>
            ProcessResult(0, 1, '', 'Some error'),
      );
      expect(await svc.getPlaylistTitle('https://x'), isNull);
    });
  });
}
