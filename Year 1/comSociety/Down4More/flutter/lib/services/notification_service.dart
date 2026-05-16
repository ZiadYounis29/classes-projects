import 'dart:io';

import 'package:flutter/foundation.dart';

/// OS-level desktop notifications with zero external dependencies.
///
/// Uses native CLI tools that ship with each OS:
///   Linux   → notify-send  (libnotify-bin, present on most distros)
///   macOS   → osascript    (built-in)
///   Windows → PowerShell   (built-in, Win 10+)
///
/// All methods are fire-and-forget — failures are silently swallowed so a
/// missing notify-send or blocked PowerShell never interrupts a download.
///
/// Call [NotificationService.init] once at startup, then use
/// [notifyFinished] and [notifyBatchFinished] from anywhere in the app.
class NotificationService {
  NotificationService._();

  /// Set to false to suppress all notifications. Controlled by AppSettings.
  static bool enabled = true;

  static bool get _isDesktop =>
      !kIsWeb &&
      (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  /// No-op on this implementation — kept for API compatibility with callers
  /// that call init() at startup.
  static Future<void> init() async {}

  /// Show a "download complete" toast with the video title as the body.
  static Future<void> notifyFinished(String videoTitle) async {
    if (!enabled || !_isDesktop) return;
    final title = 'Download complete';
    final body  = videoTitle.isEmpty ? 'Your file is ready.' : videoTitle;
    await _send(title, body);
  }

  /// Show a summary toast when a whole batch / playlist finishes.
  static Future<void> notifyBatchFinished(int count, String groupName) async {
    if (!enabled || !_isDesktop) return;
    final label = count == 1 ? '1 item' : '$count items';
    final title = groupName.isNotEmpty ? 'Down4More — $groupName' : 'Down4More';
    final body  = '$label downloaded successfully.';
    await _send(title, body);
  }

  // ── Internal dispatcher ───────────────────────────────────────────────────

  static Future<void> _send(String title, String body) async {
    try {
      if (Platform.isLinux)   await _sendLinux(title, body);
      if (Platform.isMacOS)   await _sendMacOS(title, body);
      if (Platform.isWindows) await _sendWindows(title, body);
    } catch (_) {}
  }

  /// notify-send ships with libnotify-bin on Debian/Ubuntu/Fedora/Arch.
  /// If it's missing the process simply throws and we swallow it.
  static Future<void> _sendLinux(String title, String body) async {
    await Process.run('notify-send', [
      '--app-name', 'Down4More',
      '--icon', 'dialog-information',
      '--expire-time', '5000',
      _esc(title),
      _esc(body),
    ]);
  }

  /// osascript is always available on macOS.
  static Future<void> _sendMacOS(String title, String body) async {
    final script =
        'display notification "${_esc(body)}" with title "${_esc(title)}"';
    await Process.run('osascript', ['-e', script]);
  }

  /// Uses the Windows.UI.Notifications COM API via a short PowerShell snippet.
  /// Works on Windows 10 / 11 without any extra packages.
  static Future<void> _sendWindows(String title, String body) async {
    final ps = '''
\$app = 'Down4More'
[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
\$xml = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent('ToastText02')
\$xml.GetElementsByTagName('text')[0].AppendChild(\$xml.CreateTextNode('${_esc(title)}')) | Out-Null
\$xml.GetElementsByTagName('text')[1].AppendChild(\$xml.CreateTextNode('${_esc(body)}')) | Out-Null
\$toast = [Windows.UI.Notifications.ToastNotification]::new(\$xml)
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier(\$app).Show(\$toast)
''';
    await Process.run(
      'powershell',
      ['-NoProfile', '-NonInteractive', '-Command', ps],
    );
  }

  /// Escape double-quotes and backslashes so titles/bodies don't break the
  /// shell commands above.
  static String _esc(String s) =>
      s.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
}
