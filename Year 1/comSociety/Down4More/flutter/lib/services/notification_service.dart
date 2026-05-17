import 'dart:io';

import 'package:flutter/foundation.dart';

/// OS-level desktop notifications with zero external dependencies.
///
/// Uses native CLI tools that ship with each OS:
///   Linux   → notify-send  (libnotify-bin — needs to be installed on most
///             distros). On boot we probe for the binary; if it's missing
///             [isAvailable] is `false` and every notify call becomes a
///             no-op.
///   macOS   → osascript    (built-in)
///   Windows → PowerShell   (built-in, Win 10+) — uses
///             `Windows.UI.Notifications` via a P/Invoked toast.
///
/// All public methods are fire-and-forget — failures are logged with
/// [debugPrint] (silent in release builds) but never thrown, so a missing
/// notify-send or blocked PowerShell never interrupts a download.
///
/// Call [NotificationService.init] once at startup, then use
/// [notifyFinished] and [notifyBatchFinished] from anywhere in the app.
class NotificationService {
  NotificationService._();

  /// Set to `false` to suppress all notifications. Controlled by AppSettings.
  static bool enabled = true;

  /// `true` once [init] has confirmed the OS toast mechanism is reachable.
  /// On Linux this becomes `false` if `notify-send` (libnotify-bin) is
  /// missing — the user can fix this with `apt install libnotify-bin` (or
  /// the equivalent on their distro) and a session restart.
  static bool _available = false;
  static bool get isAvailable => _available;

  static bool get _isDesktop =>
      !kIsWeb &&
      (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  /// Probe the OS toast mechanism. Currently this only matters on Linux,
  /// where we check for `notify-send` on the PATH; macOS and Windows ship
  /// their toast tools natively so we treat them as always available.
  static Future<void> init() async {
    if (!_isDesktop) {
      _available = false;
      return;
    }
    if (Platform.isLinux) {
      try {
        final result = await Process.run('which', ['notify-send']);
        _available = result.exitCode == 0;
        if (!_available) {
          debugPrint(
              'NotificationService: notify-send not found on PATH. '
              'Install libnotify-bin (apt install libnotify-bin) to enable '
              'desktop notifications.');
        }
      } catch (e) {
        _available = false;
        debugPrint('NotificationService: probe for notify-send threw: $e');
      }
    } else {
      _available = true;
    }
  }

  /// Show a "download complete" toast with the video title as the body.
  static Future<void> notifyFinished(String videoTitle) async {
    if (!enabled || !_available) return;
    const title = 'Download complete';
    final body  = videoTitle.isEmpty ? 'Your file is ready.' : videoTitle;
    await _send(title, body);
  }

  /// Show a summary toast when a whole batch / playlist finishes.
  static Future<void> notifyBatchFinished(int count, String groupName) async {
    if (!enabled || !_available) return;
    final label = count == 1 ? '1 item' : '$count items';
    final title = groupName.isNotEmpty ? 'Down4More — $groupName' : 'Down4More';
    final body  = '$label downloaded successfully.';
    await _send(title, body);
  }

  // ── Internal dispatcher ───────────────────────────────────────────────────

  static Future<void> _send(String title, String body) async {
    try {
      if (Platform.isLinux) {
        await _sendLinux(title, body);
      } else if (Platform.isMacOS) {
        await _sendMacOS(title, body);
      } else if (Platform.isWindows) {
        await _sendWindows(title, body);
      }
    } catch (e) {
      debugPrint('NotificationService: failed to send toast: $e');
    }
  }

  /// `notify-send` ships with `libnotify-bin` on Debian / Ubuntu / Fedora /
  /// Arch. [Process.run] passes argv directly to the binary so no shell
  /// escaping is required on the title / body strings — passing the raw
  /// values is correct, the previous implementation incorrectly escaped
  /// `\` and `"` which then rendered literally in the toast.
  static Future<void> _sendLinux(String title, String body) async {
    await Process.run('notify-send', [
      '--app-name', 'Down4More',
      '--icon', 'dialog-information',
      '--expire-time', '5000',
      title,
      body,
    ]);
  }

  /// `osascript` is always available on macOS. We embed the title and body
  /// inside an AppleScript string literal, so we escape backslashes and
  /// double-quotes.
  static Future<void> _sendMacOS(String title, String body) async {
    final script =
        'display notification "${_escAppleScript(body)}" '
        'with title "${_escAppleScript(title)}"';
    await Process.run('osascript', ['-e', script]);
  }

  /// Uses the `Windows.UI.Notifications` COM API via a short PowerShell
  /// snippet. The title and body are embedded inside PowerShell single-
  /// quoted strings, where the only special character is the single quote
  /// itself (doubled to escape: `'` → `''`).
  static Future<void> _sendWindows(String title, String body) async {
    final t = _escPowerShellSingle(title);
    final b = _escPowerShellSingle(body);
    final ps = '''
\$ErrorActionPreference="Stop"
\$app = 'Down4More'
[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
\$xml = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent('ToastText02')
\$xml.GetElementsByTagName('text')[0].AppendChild(\$xml.CreateTextNode('$t')) | Out-Null
\$xml.GetElementsByTagName('text')[1].AppendChild(\$xml.CreateTextNode('$b')) | Out-Null
\$toast = [Windows.UI.Notifications.ToastNotification]::new(\$xml)
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier(\$app).Show(\$toast)
''';
    final result = await Process.run(
      'powershell',
      ['-NoProfile', '-NonInteractive', '-Command', ps],
    );
    if (result.exitCode != 0) {
      debugPrint(
          'NotificationService: Windows toast failed: ${result.stderr}');
    }
  }

  /// Escape backslash and double-quote for use inside an AppleScript
  /// string literal: `"... \"foo\" ..."`.
  static String _escAppleScript(String s) =>
      s.replaceAll(r'\', r'\\').replaceAll('"', r'\"');

  /// Escape for use inside a PowerShell single-quoted string. Inside
  /// `'...'` PowerShell does NOT process backslash escapes — the only
  /// special character is the single quote itself, which is doubled to
  /// produce a literal `'`. All other characters (`\`, `"`, `$`, `` ` ``)
  /// pass through verbatim.
  static String _escPowerShellSingle(String s) =>
      s.replaceAll("'", "''");
}
