import 'dart:convert';
import 'dart:io';

import 'package:down4more/controllers/single_download_controller.dart';
import 'package:down4more/models/download_progress.dart';
import 'package:down4more/services/ytdlp_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SingleDownloadController state transitions', () {
    test('idle → fetching → ready on a successful metadata fetch', () async {
      final svc = YtDlpService(
        executable: 'fake-yt-dlp',
        processRunner: (exe, args) async => ProcessResult(
          0,
          0,
          jsonEncode({
            'title': 'Test',
            'uploader': 'C',
            'duration': 60,
            'formats': <Map<String, dynamic>>[
              {'format_id': '137', 'height': 1080, 'filesize': 1000},
            ],
          }),
          '',
        ),
      );
      final c = SingleDownloadController(
        service: svc,
        defaultOutputDir: () async => '/tmp',
      );

      final phases = <DownloadPhase>[];
      c.addListener(() => phases.add(c.progress.phase));

      await c.fetchMetadata('https://example.com/v');

      expect(phases, contains(DownloadPhase.fetchingMetadata));
      expect(phases.last, DownloadPhase.ready);
      expect(c.metadata, isNotNull);
      expect(c.metadata!.title, 'Test');
      expect(c.selectedFormat, isNotNull);
    });

    test('idle → fetching → error on yt-dlp failure', () async {
      final svc = YtDlpService(
        executable: 'fake-yt-dlp',
        processRunner: (exe, args) async =>
            ProcessResult(0, 1, '', 'ERROR: video unavailable'),
      );
      final c = SingleDownloadController(
        service: svc,
        defaultOutputDir: () async => '/tmp',
      );
      await c.fetchMetadata('https://example.com/v');
      expect(c.progress.phase, DownloadPhase.error);
      expect(c.progress.errorMessage, contains('video unavailable'));
      expect(c.metadata, isNull);
    });

    test('selectFormat updates the chosen quality and notifies', () async {
      final svc = YtDlpService(
        executable: 'fake-yt-dlp',
        processRunner: (exe, args) async => ProcessResult(
          0,
          0,
          jsonEncode({
            'title': 'T',
            'uploader': '',
            'duration': 10,
            'formats': <Map<String, dynamic>>[
              {'format_id': '137', 'height': 1080, 'filesize': 1000},
              {'format_id': '136', 'height': 720, 'filesize': 500},
            ],
          }),
          '',
        ),
      );
      final c = SingleDownloadController(
        service: svc,
        defaultOutputDir: () async => '/tmp',
      );
      await c.fetchMetadata('https://example.com/v');

      final originalId = c.selectedFormat!.id;
      var calls = 0;
      c.addListener(() => calls++);

      // Pick a different rung
      final other =
          c.metadata!.formats.firstWhere((f) => f.id != originalId);
      c.selectFormat(other);
      expect(c.selectedFormat!.id, other.id);
      expect(calls, greaterThanOrEqualTo(1));
    });

    test('reset() goes back to idle and clears metadata', () async {
      final svc = YtDlpService(
        executable: 'fake-yt-dlp',
        processRunner: (exe, args) async => ProcessResult(
          0,
          0,
          jsonEncode({
            'title': 'T',
            'uploader': '',
            'duration': 10,
            'formats': <Map<String, dynamic>>[
              {'format_id': '137', 'height': 1080, 'filesize': 1000},
            ],
          }),
          '',
        ),
      );
      final c = SingleDownloadController(
        service: svc,
        defaultOutputDir: () async => '/tmp',
      );
      await c.fetchMetadata('https://example.com/v');
      expect(c.progress.phase, DownloadPhase.ready);

      c.reset();
      expect(c.progress.phase, DownloadPhase.idle);
      expect(c.metadata, isNull);
      expect(c.selectedFormat, isNull);
    });
  });
}
