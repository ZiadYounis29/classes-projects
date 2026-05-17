import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Resolves the absolute path of an external command-line binary that the
/// app shells out to.
///
/// On **Linux / macOS** we trust the system [PATH] — yt-dlp ships in apt /
/// brew / pacman, ffmpeg is essentially everywhere, and users following the
/// install docs will already have both. The resolver just returns the bare
/// name and lets the OS resolver do its job.
///
/// On **Windows** we look for the binary *next to the running `.exe`* first
/// (i.e. inside the install directory of Down4More), so the user does not
/// need to add yt-dlp.exe / ffmpeg.exe to `PATH` manually. The Inno Setup
/// installer copies both binaries into that directory at install time. If
/// the bundled copy is missing for any reason (e.g. someone is running a
/// `flutter run -d windows` dev build) we still fall back to `PATH` so the
/// developer flow keeps working.
///
/// On **Android / iOS** there is no notion of "shell out to a binary" — the
/// download backend must be a JVM library on Android and there is no Android
/// build of yt-dlp anyway. Calling [ytDlp] or [ffmpeg] on those platforms
/// throws [UnsupportedError] so the failure is loud rather than silent.
class ExternalBinary {
  ExternalBinary._();

  /// Returns the path / command to use when launching yt-dlp.
  static Future<String> ytDlp() => _resolve('yt-dlp');

  /// Returns the path / command to use when launching ffmpeg.
  static Future<String> ffmpeg() => _resolve('ffmpeg');

  static Future<String> _resolve(String name) async {
    if (kIsWeb) {
      throw UnsupportedError(
        'External binaries are not available on the web build.',
      );
    }
    if (Platform.isAndroid || Platform.isIOS) {
      throw UnsupportedError(
        'External binary "$name" is not available on mobile. '
        'Mobile builds must use a platform-native download backend.',
      );
    }
    if (Platform.isWindows) {
      // Look for a bundled binary next to the running .exe — this is what
      // the Inno Setup installer ships.
      final exeDir = p.dirname(Platform.resolvedExecutable);
      final candidates = <String>[
        p.join(exeDir, '$name.exe'),
        p.join(exeDir, 'bin', '$name.exe'),
      ];
      for (final candidate in candidates) {
        if (await File(candidate).exists()) {
          return candidate;
        }
      }
      // Fall back to PATH (covers `flutter run -d windows` dev builds where
      // nothing is installed alongside the runner).
      return '$name.exe';
    }
    // Linux / macOS: trust PATH.
    return name;
  }
}
