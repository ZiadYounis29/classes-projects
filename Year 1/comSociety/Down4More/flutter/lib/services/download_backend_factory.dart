import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import 'android_backend_stub.dart';
import 'android_ytdlp_backend.dart';
import 'download_backend.dart';
import 'ytdlp_service.dart';

/// Pick the right [DownloadBackend] for the platform Down4More is running on.
///
/// - Linux / macOS / Windows  -> [YtDlpService] (shells out to the
///   yt-dlp + ffmpeg CLI binaries; bundled on Windows, on PATH elsewhere).
/// - Android                  -> [AndroidYtDlpBackend] (bridges to the
///   `youtubedl-android` JVM library through the [YtDlpPlugin] platform
///   channel pair).
/// - iOS                      -> [AndroidBackendStub] (Apple's sandbox
///   forbids the subprocess approach yt-dlp depends on; we surface a
///   friendly error rather than crash on launch).
/// - Web                      -> [AndroidBackendStub] for the same reason.
///
/// Controllers depend on [DownloadBackend], never on this function or on a
/// concrete class, so tests can pass any backend implementation they like.
DownloadBackend createDefaultBackend() {
  if (kIsWeb) return const AndroidBackendStub();
  if (Platform.isAndroid) return AndroidYtDlpBackend();
  if (Platform.isIOS) return const AndroidBackendStub();
  return YtDlpService();
}
