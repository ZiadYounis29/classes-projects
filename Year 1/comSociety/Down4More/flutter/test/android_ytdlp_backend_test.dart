import 'dart:async';
import 'dart:convert';

import 'package:down4more/models/download_progress.dart';
import 'package:down4more/models/subtitle_settings.dart';
import 'package:down4more/models/video_metadata.dart';
import 'package:down4more/services/android_ytdlp_backend.dart';
import 'package:down4more/services/download_backend.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-process fake for the Kotlin-side EventChannel. Tests push events into
/// the controller; the backend's stream wires up through Flutter's binary
/// messenger so we exercise the real platform-channel encoding path.
class _FakeEventChannel {
  _FakeEventChannel(this.name);
  final String name;
  final StreamController<dynamic> _controller =
      StreamController<dynamic>.broadcast();

  EventChannel get channel => EventChannel(name);

  void start() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(channel, MockStreamHandler.inline(
      onListen: (arguments, sink) {
        _controller.stream.listen(
          (event) => sink.success(event),
          onError: (Object e) =>
              sink.error(code: 'fake_error', message: e.toString()),
          onDone: sink.endOfStream,
        );
      },
    ));
  }

  void emit(Map<String, dynamic> event) => _controller.add(event);

  Future<void> close() async {
    await _controller.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(channel, null);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Shared helpers ──────────────────────────────────────────────────────

  /// Stand-in [VideoMetadata] for download() tests. Only the fields read by
  /// `_buildDownloadArgs` are meaningful; the rest are placeholders.
  VideoMetadata testMetadata({Duration? duration}) => VideoMetadata(
        url: 'https://youtu.be/dQw4w9WgXcQ',
        title: 'Test Video',
        uploader: 'Tester',
        duration: duration ?? const Duration(minutes: 3, seconds: 32),
        thumbnailUrl: 'https://example.com/thumb.jpg',
        formats: const [],
      );

  VideoFormat testFormat({bool audio = false}) => VideoFormat(
        id: audio ? 'bestaudio' : '137+140',
        label: audio ? 'Audio · m4a' : '1080p · MP4',
        ext: audio ? 'm4a' : 'mp4',
        height: audio ? null : 1080,
        fileSize: 12_345_678,
        note: 'test',
        isAudioOnly: audio,
      );

  // ── Surface tests ────────────────────────────────────────────────────

  test('AndroidYtDlpBackend implements DownloadBackend', () {
    final backend = AndroidYtDlpBackend(
      methodChannel: const MethodChannel('test/method'),
      eventChannel: const EventChannel('test/events'),
    );
    expect(backend, isA<DownloadBackend>());
  });

  // ── fetchMetadata ────────────────────────────────────────────────────

  group('fetchMetadata', () {
    const methodName = 'down4more/yt_dlp_test_metadata';
    late AndroidYtDlpBackend backend;
    late List<MethodCall> calls;

    setUp(() {
      calls = [];
      backend = AndroidYtDlpBackend(
        methodChannel: const MethodChannel(methodName),
        eventChannel: const EventChannel('test/events_unused'),
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(methodName), null);
    });

    void mockHandler(Future<Object?> Function(MethodCall) handler) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(methodName),
              (call) async {
        calls.add(call);
        return handler(call);
      });
    }

    test('sends init then getInfo and parses --dump-single-json output',
        () async {
      mockHandler((call) async {
        if (call.method == 'init') return null;
        if (call.method == 'getInfo') {
          return <String, Object?>{
            'exitCode': 0,
            'stdout': jsonEncode({
              'id': 'abc',
              'title': 'Hello World',
              'duration': 42,
              'thumbnail': 'https://t.example.com/t.jpg',
              'formats': <Map<String, Object?>>[
                {
                  'format_id': '18',
                  'ext': 'mp4',
                  'height': 360,
                  'filesize': 100,
                  'format_note': '360p',
                  'vcodec': 'avc1',
                  'acodec': 'aac',
                },
              ],
            }),
            'stderr': '',
          };
        }
        fail('Unexpected call: ${call.method}');
      });

      final metadata =
          await backend.fetchMetadata('https://youtu.be/abc');

      expect(metadata.url, 'https://youtu.be/abc');
      expect(metadata.title, 'Hello World');
      expect(metadata.duration, const Duration(seconds: 42));
      expect(calls.map((c) => c.method).toList(),
          equals(['init', 'getInfo']));
      final args =
          (calls[1].arguments as Map).cast<String, dynamic>();
      expect(args['url'], 'https://youtu.be/abc');
      expect(args['args'], contains('--dump-single-json'));
      expect(args['args'], contains('--no-cache-dir'));
    });

    test('empty URL throws YtDlpException without calling the plugin',
        () async {
      mockHandler((_) async => null);
      await expectLater(
        () => backend.fetchMetadata('  '),
        throwsA(isA<YtDlpException>()),
      );
      expect(calls, isEmpty);
    });

    test('non-zero exitCode surfaces stderr in YtDlpException', () async {
      mockHandler((call) async {
        if (call.method == 'init') return null;
        return <String, Object?>{
          'exitCode': 1,
          'stdout': '',
          'stderr': 'ERROR: Video unavailable',
        };
      });
      await expectLater(
        () => backend.fetchMetadata('https://youtu.be/bad'),
        throwsA(predicate(
          (e) => e is YtDlpException &&
              e.message.contains('Video unavailable'),
        )),
      );
    });

    test('init PlatformException is wrapped in YtDlpException', () async {
      mockHandler((call) async {
        if (call.method == 'init') {
          throw PlatformException(
            code: 'init_failed',
            message: 'youtubedl-android init failed',
          );
        }
        return null;
      });
      await expectLater(
        () => backend.fetchMetadata('https://youtu.be/x'),
        throwsA(predicate(
          (e) => e is YtDlpException && e.message.contains('init'),
        )),
      );
    });
  });

  // ── fetchPlaylist ────────────────────────────────────────────────────

  group('fetchPlaylist', () {
    const methodName = 'down4more/yt_dlp_test_playlist';

    test('parses one JSON entry per line and drops blank lines', () async {
      final backend = AndroidYtDlpBackend(
        methodChannel: const MethodChannel(methodName),
        eventChannel: const EventChannel('test/events_unused'),
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(methodName),
              (call) async {
        if (call.method == 'init') return null;
        return <String, Object?>{
          'exitCode': 0,
          'stdout': <String>[
            jsonEncode({'id': 'v1', 'title': 'One', 'url': 'v1'}),
            '',
            jsonEncode({'id': 'v2', 'title': 'Two', 'url': 'v2'}),
            '   ',
            jsonEncode({'id': 'v3', 'title': 'Three', 'url': 'v3'}),
          ].join('\n'),
          'stderr': '',
        };
      });

      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(const MethodChannel(methodName), null);
      });

      final entries = await backend
          .fetchPlaylist('https://www.youtube.com/playlist?list=PLxyz');
      expect(entries, hasLength(3));
      expect(entries.map((e) => e.title).toList(),
          equals(['One', 'Two', 'Three']));
      // PlaylistEntry.fromJson rewrites bare ids into watch URLs.
      expect(entries.every((e) => e.url.startsWith('https://')), isTrue);
    });
  });

  // ── getPlaylistTitle ─────────────────────────────────────────────────

  group('getPlaylistTitle', () {
    const methodName = 'down4more/yt_dlp_test_pltitle';

    test('returns the first non-empty, non-"NA" line', () async {
      final backend = AndroidYtDlpBackend(
        methodChannel: const MethodChannel(methodName),
        eventChannel: const EventChannel('test/events_unused'),
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(methodName),
              (call) async {
        if (call.method == 'init') return null;
        return <String, Object?>{
          'exitCode': 0,
          'stdout': '\nNA\n  \nMy Favourite Mix\nignored second line\n',
          'stderr': '',
        };
      });

      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(const MethodChannel(methodName), null);
      });

      expect(await backend.getPlaylistTitle('https://x/playlist'),
          'My Favourite Mix');
    });

    test('returns null for empty URL and never invokes the plugin', () async {
      final calls = <MethodCall>[];
      final backend = AndroidYtDlpBackend(
        methodChannel: const MethodChannel(methodName),
        eventChannel: const EventChannel('test/events_unused'),
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(methodName),
              (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(const MethodChannel(methodName), null);
      });

      expect(await backend.getPlaylistTitle('   '), isNull);
      expect(calls, isEmpty);
    });
  });

  // ── download (args + stream behaviour) ───────────────────────────────

  group('download', () {
    const methodName = 'down4more/yt_dlp_test_download';
    const eventName = 'down4more/yt_dlp_test_download_events';
    late AndroidYtDlpBackend backend;
    late List<MethodCall> calls;
    late _FakeEventChannel events;
    late Completer<void> startCompleter;

    setUp(() {
      calls = [];
      startCompleter = Completer<void>();
      backend = AndroidYtDlpBackend(
        methodChannel: const MethodChannel(methodName),
        eventChannel: const EventChannel(eventName),
      );
      events = _FakeEventChannel(eventName)..start();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(methodName),
              (call) async {
        calls.add(call);
        if (call.method == 'init') return null;
        if (call.method == 'startDownload') {
          startCompleter.complete();
          return null;
        }
        if (call.method == 'cancelDownload') return null;
        return null;
      });
    });

    tearDown(() async {
      await events.close();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(methodName), null);
    });

    test('builds yt-dlp args mirroring YtDlpService and ships through plugin',
        () async {
      final handle = backend.download(
        metadata: testMetadata(),
        format: testFormat(),
        outputDir: '/storage/emulated/0/Download',
        outputExt: 'mp4',
        rateLimit: '2M',
        subtitles: const SubtitleSettings(
          enabled: true,
          language: 'en',
          format: 'srt',
          embed: true,
        ),
      );

      // Drain the stream so the handle stays alive until we tear it down.
      final drain = handle.stream.toList();

      await startCompleter.future;
      final start = calls.firstWhere((c) => c.method == 'startDownload');
      final args = ((start.arguments as Map)['args'] as List).cast<String>();

      expect(args, contains('--newline'));
      expect(args, contains('--no-playlist'));
      expect(args, contains('--no-cache-dir'));
      expect(args, contains('--no-part'));
      expect(args, containsAllInOrder(['-f', '137+140']));
      expect(args, containsAllInOrder(['--merge-output-format', 'mp4']));
      expect(args, containsAllInOrder(['--rate-limit', '2M']));
      expect(args, contains('--write-subs'));
      expect(args, containsAllInOrder(['--sub-langs', 'en']));
      expect(args, contains('--embed-subs'));
      // The trailing URL is always the metadata URL.
      expect(args.last, 'https://youtu.be/dQw4w9WgXcQ');

      events.emit(<String, dynamic>{
        'downloadId':
            (start.arguments as Map)['downloadId'] as String,
        'type': 'completed',
        'exitCode': 0,
        'stdout': '',
        'stderr': '',
      });
      await drain;
    });

    test('audio format swaps to -x --audio-format and skips merge flag',
        () async {
      final handle = backend.download(
        metadata: testMetadata(),
        format: testFormat(audio: true),
        outputDir: '/d',
        outputExt: 'mp3',
      );
      final drain = handle.stream.toList();
      await startCompleter.future;
      final args =
          ((calls.firstWhere((c) => c.method == 'startDownload').arguments
                  as Map)['args'] as List)
              .cast<String>();
      expect(args, containsAllInOrder(['-x', '--audio-format', 'mp3']));
      expect(args, isNot(contains('--merge-output-format')));

      events.emit(<String, dynamic>{
        'downloadId': (calls
                .firstWhere((c) => c.method == 'startDownload')
                .arguments as Map)['downloadId'] as String,
        'type': 'completed',
        'exitCode': 0,
        'stdout': '',
        'stderr': '',
      });
      await drain;
    });

    test('trim window uses --download-sections in *HH:MM:SS-HH:MM:SS form',
        () async {
      final handle = backend.download(
        metadata: testMetadata(),
        format: testFormat(),
        outputDir: '/d',
        trimStart: const Duration(seconds: 5),
        trimEnd: const Duration(minutes: 1, seconds: 30),
      );
      final drain = handle.stream.toList();
      await startCompleter.future;
      final args =
          ((calls.firstWhere((c) => c.method == 'startDownload').arguments
                  as Map)['args'] as List)
              .cast<String>();
      expect(
        args,
        containsAllInOrder([
          '--download-sections',
          '*00:00:05-00:01:30',
        ]),
      );
      expect(args, contains('--force-keyframes-at-cuts'));

      events.emit(<String, dynamic>{
        'downloadId': (calls
                .firstWhere((c) => c.method == 'startDownload')
                .arguments as Map)['downloadId'] as String,
        'type': 'cancelled',
      });
      await drain;
    });

    test('stream emits progress / completed events and ignores other ids',
        () async {
      final handle = backend.download(
        metadata: testMetadata(),
        format: testFormat(),
        outputDir: '/d',
      );

      final emitted = <DownloadProgress>[];
      final sub = handle.stream.listen(emitted.add);

      await startCompleter.future;
      final downloadId =
          (calls.firstWhere((c) => c.method == 'startDownload').arguments
              as Map)['downloadId'] as String;

      // A stray event for a DIFFERENT download must not leak into our stream.
      events.emit(<String, dynamic>{
        'downloadId': 'someone-elses-download',
        'type': 'progress',
        'percent': 99.0,
        'etaSeconds': 0,
        'line': '[download] 99% of 100MiB',
      });

      events.emit(<String, dynamic>{
        'downloadId': downloadId,
        'type': 'progress',
        'percent': 12.5,
        'etaSeconds': 30,
        'line': '[download]  12.5% of  100.00MiB at 5.00MiB/s ETA 00:30',
      });

      events.emit(<String, dynamic>{
        'downloadId': downloadId,
        'type': 'completed',
        'exitCode': 0,
        'stdout': '',
        'stderr': '',
      });

      await handle.stream.drain<void>();
      await sub.cancel();

      expect(emitted.length, greaterThanOrEqualTo(2));
      expect(emitted.first.phase, DownloadPhase.downloading);
      expect(emitted.last.phase, DownloadPhase.finished);
      expect(emitted.last.percent, 100);
    });

    test('non-zero completed event becomes a DownloadPhase.error', () async {
      final handle = backend.download(
        metadata: testMetadata(),
        format: testFormat(),
        outputDir: '/d',
      );
      final drain = handle.stream.toList();
      await startCompleter.future;
      final downloadId =
          (calls.firstWhere((c) => c.method == 'startDownload').arguments
              as Map)['downloadId'] as String;

      events.emit(<String, dynamic>{
        'downloadId': downloadId,
        'type': 'completed',
        'exitCode': 1,
        'stdout': '',
        'stderr': 'ERROR: HTTP 403',
      });

      final events_ = await drain;
      expect(events_.last.phase, DownloadPhase.error);
      expect(events_.last.errorMessage, contains('403'));
    });

    test('error event surfaces the plugin message verbatim', () async {
      final handle = backend.download(
        metadata: testMetadata(),
        format: testFormat(),
        outputDir: '/d',
      );
      final drain = handle.stream.toList();
      await startCompleter.future;
      final downloadId =
          (calls.firstWhere((c) => c.method == 'startDownload').arguments
              as Map)['downloadId'] as String;
      events.emit(<String, dynamic>{
        'downloadId': downloadId,
        'type': 'error',
        'message': 'Disk full',
      });
      final list = await drain;
      expect(list.single.phase, DownloadPhase.error);
      expect(list.single.errorMessage, 'Disk full');
    });

    test('cancel() routes through the cancelDownload method call', () async {
      final handle = backend.download(
        metadata: testMetadata(),
        format: testFormat(),
        outputDir: '/d',
      );
      final drain = handle.stream.toList();
      await startCompleter.future;
      handle.cancel();

      // Drive a cancelled event so the stream closes.
      final downloadId =
          (calls.firstWhere((c) => c.method == 'startDownload').arguments
              as Map)['downloadId'] as String;
      events.emit(<String, dynamic>{
        'downloadId': downloadId,
        'type': 'cancelled',
      });

      final list = await drain;
      expect(list.last.phase, DownloadPhase.cancelled);
      expect(
        calls.where((c) => c.method == 'cancelDownload').length,
        1,
      );
    });
  });
}
