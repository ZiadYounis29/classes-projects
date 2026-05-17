import 'package:down4more/models/download_progress.dart';
import 'package:down4more/models/video_metadata.dart';
import 'package:down4more/services/android_backend_stub.dart';
import 'package:down4more/services/download_backend.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AndroidBackendStub', () {
    const stub = AndroidBackendStub();

    test('is a DownloadBackend', () {
      expect(stub, isA<DownloadBackend>());
    });

    test('fetchMetadata throws YtDlpException with the user-facing message',
        () {
      expect(
        () => stub.fetchMetadata('https://example.com/v'),
        throwsA(
          isA<YtDlpException>().having(
            (e) => e.message,
            'message',
            equals(AndroidBackendStub.unsupportedMessage),
          ),
        ),
      );
    });

    test('fetchPlaylist throws YtDlpException with the user-facing message',
        () {
      expect(
        () => stub.fetchPlaylist('https://example.com/p'),
        throwsA(isA<YtDlpException>()),
      );
    });

    test('getPlaylistTitle returns null (does not throw) so default-name '
        'fallback in PlaylistController still works', () async {
      expect(await stub.getPlaylistTitle('https://example.com/p'), isNull);
    });

    test('download returns a failed handle that emits exactly one error '
        'event and closes the stream', () async {
      final handle = stub.download(
        metadata: const VideoMetadata(
          url: 'https://example.com/v',
          title: 't',
          uploader: 'u',
          duration: Duration(seconds: 1),
          thumbnailUrl: null,
          formats: [],
        ),
        format: const VideoFormat(
          id: 'best',
          label: 'Best available',
          ext: 'mp4',
          height: null,
          fileSize: null,
          note: '',
          isAudioOnly: false,
        ),
        outputDir: '/tmp/down4more',
      );

      final events = await handle.stream.toList();
      expect(events, hasLength(1));
      expect(events.single.phase, DownloadPhase.error);
      expect(
        events.single.errorMessage,
        equals(AndroidBackendStub.unsupportedMessage),
      );

      // pause / resume / cancel are no-ops on a failed handle. They should
      // never throw — the UI calls these freely.
      expect(() => handle.pause(), returnsNormally);
      expect(() => handle.resume(), returnsNormally);
      expect(() => handle.cancel(), returnsNormally);
    });

    test('the unsupportedMessage explains *what* is missing and what to do',
        () {
      final msg = AndroidBackendStub.unsupportedMessage;
      // We deliberately surface "Android" and a pointer to the desktop build
      // so users land in the error card with actionable context, not just
      // "something went wrong".
      expect(msg, contains('Android'));
      expect(msg.toLowerCase(), contains('desktop'));
    });

    test('openFile returns false (without throwing) so the UI shows its '
        '"couldn\'t open" snackbar instead of crashing', () async {
      expect(await stub.openFile('/whatever'), isFalse);
    });

    test('openFolder returns false (without throwing) on the stub backend',
        () async {
      expect(await stub.openFolder('/whatever'), isFalse);
    });
  });
}
