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

    // ── ffmpeg time= lines (trim mode) ───────────────────────────────────

    test(
        'parses ffmpeg time= into a percent of the trim segment when '
        'trimDuration is supplied', () {
      // 60s trim, we're 30s in → ~50%.
      final p = parseProgressLine(
        'frame= 1234 fps=30.0 q=24.0 size=   12345kB time=00:00:30.00 '
        'bitrate=2392.4kbits/s speed=1.50x',
        trimDuration: const Duration(seconds: 60),
      );
      expect(p, isNotNull);
      expect(p!.phase, DownloadPhase.downloading);
      expect(p.percent, closeTo(50.0, 0.5),
          reason: '30s elapsed of a 60s trim should report ~50%');
      // ETA = remaining (30s) / speed (1.5x) = 20s.
      expect(p.eta!.inSeconds, inInclusiveRange(19, 21));
      // bitrate (2392.4 kbits/s) * 1024 / 8 * 1.5 ≈ 459_341 B/s.
      expect(p.speedBytesPerSecond, closeTo(459_341, 5000));
      expect(p.message, contains('1.5×'));
    });

    test(
        'ffmpeg time= without trimDuration emits null percent/eta but still '
        'surfaces the speed in the message', () {
      final p = parseProgressLine(
        'frame=  60 fps=30.0 q=24.0 size=     500kB time=00:00:02.00 '
        'bitrate=2048.0kbits/s speed=2.00x',
      );
      expect(p, isNotNull);
      expect(p!.percent, isNull,
          reason: 'no trimDuration → cannot compute a percent');
      expect(p.eta, isNull);
      expect(p.message, contains('2.0×'));
    });

    test('ffmpeg time= clamps percent to 100 when ffmpeg overshoots',
        () {
      // ffmpeg's `time=` is occasionally a few ms past the requested
      // duration on the last line — should still cap at 100%.
      final p = parseProgressLine(
        'frame= 1800 fps=30.0 q=24.0 size=   45000kB time=00:01:00.50 '
        'bitrate=2400.0kbits/s speed=1.00x',
        trimDuration: const Duration(seconds: 60),
      );
      expect(p, isNotNull);
      expect(p!.percent, closeTo(100.0, 0.001));
    });

    test('ffmpeg time= falls back gracefully when speed= is missing',
        () {
      // Older ffmpeg builds (or the very first line) omit `speed=`.
      final p = parseProgressLine(
        'frame=  60 fps= 0.0 q=0.0 size=N/A time=00:00:02.00 bitrate=N/A',
        trimDuration: const Duration(seconds: 10),
      );
      expect(p, isNotNull);
      expect(p!.percent, closeTo(20.0, 0.5));
      // No speedX → ETA can't be computed.
      expect(p.eta, isNull);
      // No speedX → can't render the realtime multiplier.
      expect(p.message, equals('Trimming segment with ffmpeg…'));
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
          // Video-only streams: vcodec set, acodec='none'. parseFormatList
          // requires this to count an entry into the per-height size map.
          {
            'format_id': '137',
            'height': 1080,
            'vcodec': 'avc1.640028',
            'acodec': 'none',
            'filesize': 50 * 1024 * 1024,
          },
          {
            'format_id': '136',
            'height': 720,
            'vcodec': 'avc1.4d401f',
            'acodec': 'none',
            'filesize': 25 * 1024 * 1024,
          },
          // Audio-only stream.
          {
            'format_id': '140',
            'vcodec': 'none',
            'acodec': 'mp4a.40.2',
            'filesize': 5 * 1024 * 1024,
          },
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
