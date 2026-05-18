import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:permission_handler/permission_handler.dart';

/// Best-effort prompt for `POST_NOTIFICATIONS` on Android 13+ (API 33).
///
/// We use this so the foreground-service notification posted by
/// `DownloadForegroundService` actually appears in the system shade — without
/// the permission the service still runs (and Android keeps the app alive),
/// but the user gets no visible indicator that a download is in flight.
///
/// On older Android versions, on non-Android platforms, and on the web this
/// is a no-op. The call is idempotent: if the user has already granted or
/// permanently denied the permission, `Permission.notification.request()`
/// returns immediately without re-prompting.
Future<bool> ensureNotificationPermission() async {
  if (kIsWeb || !Platform.isAndroid) return true;
  try {
    final status = await Permission.notification.status;
    if (status.isGranted) return true;
    if (status.isPermanentlyDenied) return false;
    final result = await Permission.notification.request();
    return result.isGranted;
  } catch (_) {
    // permission_handler can throw if the manifest lacks the permission
    // (it doesn't — we declare it) or if the Activity is null mid-rotation.
    // Either way the download itself should still run, so swallow.
    return false;
  }
}
