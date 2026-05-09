import 'dart:convert';
import 'dart:io';

import 'package:down4more/controllers/download_queue_controller.dart';
import 'package:down4more/models/download_progress.dart';
import 'package:down4more/models/output_format.dart';
import 'package:down4more/services/ytdlp_service.dart';
import 'package:down4more/settings/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

/// Build a queue controller wired to a fake yt-dlp that returns one canned
/// metadata response per fetchMetadata call.
DownloadQueueController _makeQueue({
  String fakeJson = '''
    {
      "title": "Fake video",
      "uploader": "U",
      "duration": 60,
      "formats": [
        {"format_id": "137", "height": 1080, "filesize": 1000,
         "vcodec": "avc1", "acodec": "none"},
        {"format_id": "140", "filesize": 100,
         "vcodec": "none", "acodec": "mp4a"}
      ]
    }
  ''',
}) {
  final svc = YtDlpService(
    executable: 'fake-yt-dlp',
    processRunner: (exe, args) async => ProcessResult(0, 0, fakeJson, ''),
  );
  return DownloadQueueController(
    appSettings: AppSettings(),
    service: svc,
  );
}

void main() {
  group('DownloadQueueController — populate', () {
    test('addUrls turns each URL into a QueueItem (title = url)', () {
      final q = _makeQueue();
      q.addUrls(['https://a.example/v1', 'https://b.example/v2', '']);
      expect(q.items.length, 2);
      expect(q.items[0].url, 'https://a.example/v1');
      expect(q.items[0].title, 'https://a.example/v1');
      expect(q.items[0].progress.phase, DownloadPhase.idle);
    });

    test('addEntries preserves the title + thumbnailUrl from playlist', () {
      final q = _makeQueue();
      q.addEntries([
        (url: 'https://a.example', title: 'Hello world', thumbnailUrl: 'https://t.example/x.jpg'),
      ]);
      expect(q.items.single.title, 'Hello world');
      expect(q.items.single.thumbnailUrl, 'https://t.example/x.jpg');
    });
  });

  group('DownloadQueueController — preview', () {
    test('previewItem populates metadata + selectedFormat', () async {
      final q = _makeQueue();
      q.addUrls(['https://a.example']);
      await q.previewItem(q.items.single);
      final item = q.items.single;
      expect(item.metadata, isNotNull);
      expect(item.metadata!.title, 'Fake video');
      expect(item.title, 'Fake video'); // adopted from metadata
      expect(item.selectedFormat, isNotNull);
      expect(item.previewError, isNull);
    });

    test('previewItem captures yt-dlp errors as previewError', () async {
      final svc = YtDlpService(
        executable: 'fake-yt-dlp',
        processRunner: (exe, args) async =>
            ProcessResult(0, 1, '', 'ERROR: Unsupported URL'),
      );
      final q = DownloadQueueController(
        appSettings: AppSettings(),
        service: svc,
      );
      q.addUrls(['https://nope']);
      await q.previewItem(q.items.single);
      expect(q.items.single.previewError, contains('Unsupported URL'));
      expect(q.items.single.metadata, isNull);
    });

    test('previewAll runs all items with bounded concurrency', () async {
      var calls = 0;
      final svc = YtDlpService(
        executable: 'fake-yt-dlp',
        processRunner: (exe, args) async {
          calls++;
          return ProcessResult(0, 0,
              jsonEncode({'title': 'T$calls', 'uploader': '', 'duration': 1, 'formats': []}),
              '');
        },
      );
      final q = DownloadQueueController(
        appSettings: AppSettings(),
        service: svc,
      );
      q.addUrls(['https://a', 'https://b', 'https://c', 'https://d']);
      await q.previewAll(concurrency: 2);
      expect(calls, 4);
      expect(q.items.every((i) => i.metadata != null), isTrue);
    });
  });

  group('DownloadQueueController — per-item cancel/retry', () {
    test('cancelItem on an idle item sets phase to cancelled', () async {
      final q = _makeQueue();
      q.addUrls(['https://a.example']);
      await q.cancelItem(q.items.single);
      expect(q.items.single.progress.phase, DownloadPhase.cancelled);
    });

    test('retryItem on idle item is a no-op (only error/cancelled trigger)',
        () async {
      // The full retryItem path also restarts the queue loop, which spawns
      // a real yt-dlp subprocess via Process.start — that's not mockable
      // through the test processRunner. So we verify the early-return guard
      // here, and leave the full retry-then-download flow to manual /
      // integration testing.
      final q = _makeQueue();
      q.addUrls(['https://a.example']);
      expect(q.items.single.progress.phase, DownloadPhase.idle);
      await q.retryItem(q.items.single);
      expect(q.items.single.progress.phase, DownloadPhase.idle);
      // Queue should NOT have been started because retryItem returned early
      // when the item wasn't in error/cancelled state.
      expect(q.isRunning, isFalse);
    });

    test('removeItem drops the item from the queue', () async {
      final q = _makeQueue();
      q.addUrls(['https://a', 'https://b']);
      await q.removeItem(q.items.first);
      expect(q.items.length, 1);
      expect(q.items.single.url, 'https://b');
    });
  });

  group('DownloadQueueController — global + per-item dropdowns', () {
    test('setGlobalOutputFormat applies to all items', () {
      final q = _makeQueue();
      q.addUrls(['https://a', 'https://b']);
      final mp3 = kAudioFormats.firstWhere((f) => f.ext == 'mp3');
      q.setGlobalOutputFormat(mp3);
      for (final item in q.items) {
        expect(item.selectedOutputFormat?.ext, 'mp3');
      }
    });

    test('setItemOutputFormat overrides only one item', () {
      final q = _makeQueue();
      q.addUrls(['https://a', 'https://b']);
      final mp4 = kVideoFormats.firstWhere((f) => f.ext == 'mp4');
      final webm = kVideoFormats.firstWhere((f) => f.ext == 'webm');
      q.setGlobalOutputFormat(mp4);
      q.setItemOutputFormat(q.items.last, webm);
      expect(q.items.first.selectedOutputFormat?.ext, 'mp4');
      expect(q.items.last.selectedOutputFormat?.ext, 'webm');
    });
  });

  group('DownloadQueueController — group folder', () {
    test('group folder is OFF by default', () {
      final q = _makeQueue();
      expect(q.groupFolderEnabled, isFalse);
      expect(q.groupFolderName, isEmpty);
    });

    test('setGroupFolder updates state and notifies', () {
      final q = _makeQueue();
      var notifications = 0;
      q.addListener(() => notifications++);
      q.setGroupFolder(enabled: true, name: 'My Mix');
      expect(q.groupFolderEnabled, isTrue);
      expect(q.groupFolderName, 'My Mix');
      expect(notifications, greaterThanOrEqualTo(1));
    });

    test('setGroupFolder(name: null) leaves the existing name in place', () {
      final q = _makeQueue();
      q.setGroupFolder(enabled: true, name: 'Mix A');
      q.setGroupFolder(enabled: false);
      expect(q.groupFolderName, 'Mix A');
      expect(q.groupFolderEnabled, isFalse);
    });
  });

  group('DownloadQueueController — allDone signal', () {
    test('allDone is false on a fresh idle queue', () {
      final q = _makeQueue();
      q.addUrls(['https://a']);
      expect(q.allDone, isFalse);
    });

    test('allDone is true when every item is cancelled / errored / done',
        () async {
      final q = _makeQueue();
      q.addUrls(['https://a', 'https://b']);
      for (final item in q.items) {
        await q.cancelItem(item);
      }
      expect(q.allDone, isTrue);
    });

    test('allDone counts preview-failed items as done', () async {
      final svc = YtDlpService(
        executable: 'fake-yt-dlp',
        processRunner: (exe, args) async =>
            ProcessResult(0, 1, '', 'ERROR: Unsupported URL'),
      );
      final q = DownloadQueueController(
        appSettings: AppSettings(),
        service: svc,
      );
      q.addUrls(['https://nope']);
      await q.previewItem(q.items.single);
      expect(q.allDone, isTrue);
    });
  });
}
