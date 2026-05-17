import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import 'android_backend_stub.dart';
import 'download_backend.dart';
import 'ytdlp_service.dart';

/// Pick the right [DownloadBackend] for the platform Down4More is running on.
///
/// - Linux / macOS / Windows  -> [YtDlpService] (shells out to the
///   yt-dlp + ffmpeg CLI binaries; bundled on Windows, on PATH elsewhere).
/// - Android                  -> [AndroidBackendStub] (placeholder that
///   surfaces a friendly "not implemented yet" error; the real backend
///   based on youtubedl-android lands in a follow-up PR).
/// - iOS                      -> [AndroidBackendStub] for now. iOS will
///   never be fully supported (Apple's sandbox forbids the subprocess
///   approach yt-dlp depends on), but if someone manages to compile a
///   build we don't want it crashing on launch.
/// - Web                      -> [AndroidBackendStub] for the same reason.
///
/// Controllers depend on [DownloadBackend], never on this function or on a
/// concrete class, so tests can pass any backend implementation they like.
DownloadBackend createDefaultBackend() {
  if (kIsWeb) return const AndroidBackendStub();
  if (Platform.isAndroid || Platform.isIOS) return const AndroidBackendStub();
  return YtDlpService();
}
