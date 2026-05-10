import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/output_format.dart';

/// Persisted application preferences.
///
/// All fields are backed by [SharedPreferences] and notified to listeners on
/// change. Load once at startup via [AppSettings.load]; then pass the single
/// instance down to wherever it's needed (Settings screen + controller).
///
/// Keys are namespaced under `d4m.settings.*` to avoid collisions with the
/// theme keys (`d4m.theme.*`).
class AppSettings extends ChangeNotifier {
  AppSettings({SharedPreferences? prefs}) : _prefs = prefs;

  // ── Key constants ──────────────────────────────────────────────────────────
  static const _kDownloadDir    = 'd4m.settings.downloadDir';
  static const _kKeepPartial    = 'd4m.settings.keepPartial';
  static const _kDefaultFormat      = 'd4m.settings.defaultFormat';
  static const _kDefaultAudioFormat = 'd4m.settings.defaultAudioFormat';
  static const _kDefaultQuality = 'd4m.settings.defaultQuality';
  static const _kConcurrency    = 'd4m.settings.concurrency';
  static const _kSpeedLimit     = 'd4m.settings.speedLimit';
  static const _kAutoRetry      = 'd4m.settings.autoRetry';
  static const _kRetryDelay     = 'd4m.settings.retryDelay';
  static const _kBatchFolder    = 'd4m.settings.batchFolder';
  static const _kPlaylistFolder = 'd4m.settings.playlistFolder';

  SharedPreferences? _prefs;

  // ── Runtime values (defaults shown) ───────────────────────────────────────

  /// Absolute path to the download folder. Empty string = use platform default.
  String _downloadDir    = '';
  bool   _keepPartial    = false;
  String _defaultFormat      = 'mp4';   // video OutputFormat.ext
  String _defaultAudioFormat = 'm4a';   // audio OutputFormat.ext
  String _defaultQuality = 'best';  // 'best' | '2160p' | '1080p' | '720p' | '480p' | '360p' | 'audio'
  int    _concurrency    = 2;       // max parallel downloads (used by batch)
  String _speedLimit     = '';      // empty = unlimited; yt-dlp value e.g. '2M'
  int    _autoRetry      = 0;       // 0 = disabled
  int    _retryDelay     = 5;       // seconds between retries
  bool   _batchFolder    = true;    // default: save batch downloads into a subfolder
  bool   _playlistFolder = true;    // default: save playlist downloads into a subfolder

  // ── Public getters ─────────────────────────────────────────────────────────
  String get downloadDir    => _downloadDir;
  bool   get keepPartial    => _keepPartial;
  String get defaultFormat      => _defaultFormat;
  String get defaultAudioFormat => _defaultAudioFormat;
  String get defaultQuality => _defaultQuality;
  int    get concurrency    => _concurrency;
  String get speedLimit     => _speedLimit;
  int    get autoRetry      => _autoRetry;
  int    get retryDelay     => _retryDelay;
  bool   get batchFolder    => _batchFolder;
  bool   get playlistFolder => _playlistFolder;

  /// Convenience: whether a speed cap is configured.
  bool get hasSpeedLimit => _speedLimit.trim().isNotEmpty;

  /// The [OutputFormat] matching the current default quality category.
  /// Returns the audio format default when defaultQuality is 'audio',
  /// otherwise returns the video format default.
  OutputFormat get defaultOutputFormat {
    if (_defaultQuality == 'audio') {
      return kAudioFormats.firstWhere(
        (f) => f.ext == _defaultAudioFormat,
        orElse: () => kDefaultAudioFormat,
      );
    }
    return kVideoFormats.firstWhere(
      (f) => f.ext == _defaultFormat,
      orElse: () => kDefaultVideoFormat,
    );
  }

  // ── Setters (persist + notify) ─────────────────────────────────────────────

  Future<void> setDownloadDir(String v) async {
    _downloadDir = v;
    notifyListeners();
    await _write(_kDownloadDir, v);
  }

  Future<void> setKeepPartial(bool v) async {
    _keepPartial = v;
    notifyListeners();
    await _write(_kKeepPartial, v);
  }

  Future<void> setDefaultFormat(String v) async {
    _defaultFormat = v;
    notifyListeners();
    await _write(_kDefaultFormat, v);
  }

  Future<void> setDefaultAudioFormat(String v) async {
    _defaultAudioFormat = v;
    notifyListeners();
    await _write(_kDefaultAudioFormat, v);
  }

  Future<void> setDefaultQuality(String v) async {
    _defaultQuality = v;
    notifyListeners();
    await _write(_kDefaultQuality, v);
  }

  Future<void> setConcurrency(int v) async {
    _concurrency = v.clamp(1, 8);
    notifyListeners();
    await _write(_kConcurrency, _concurrency);
  }

  Future<void> setSpeedLimit(String v) async {
    _speedLimit = v.trim();
    notifyListeners();
    await _write(_kSpeedLimit, _speedLimit);
  }

  Future<void> setAutoRetry(int v) async {
    _autoRetry = v.clamp(0, 10);
    notifyListeners();
    await _write(_kAutoRetry, _autoRetry);
  }

  Future<void> setRetryDelay(int v) async {
    _retryDelay = v.clamp(1, 60);
    notifyListeners();
    await _write(_kRetryDelay, _retryDelay);
  }

  Future<void> setBatchFolder(bool v) async {
    _batchFolder = v;
    notifyListeners();
    await _write(_kBatchFolder, v);
  }

  Future<void> setPlaylistFolder(bool v) async {
    _playlistFolder = v;
    notifyListeners();
    await _write(_kPlaylistFolder, v);
  }

  // ── Load from disk ─────────────────────────────────────────────────────────

  Future<void> load() async {
    _prefs ??= await SharedPreferences.getInstance();
    final p = _prefs!;

    _downloadDir    = p.getString(_kDownloadDir)  ?? '';
    _keepPartial    = p.getBool(_kKeepPartial)     ?? false;
    _defaultFormat      = p.getString(_kDefaultFormat)      ?? 'mp4';
    _defaultAudioFormat = p.getString(_kDefaultAudioFormat)   ?? 'm4a';
    _defaultQuality = p.getString(_kDefaultQuality) ?? 'best';
    _concurrency    = p.getInt(_kConcurrency)      ?? 2;
    _speedLimit     = p.getString(_kSpeedLimit)    ?? '';
    _autoRetry      = p.getInt(_kAutoRetry)        ?? 0;
    _retryDelay     = p.getInt(_kRetryDelay)       ?? 5;
    _batchFolder    = p.getBool(_kBatchFolder)     ?? true;
    _playlistFolder = p.getBool(_kPlaylistFolder)  ?? true;

    notifyListeners();
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  Future<void> _write(String key, Object value) async {
    _prefs ??= await SharedPreferences.getInstance();
    final p = _prefs!;
    if (value is String)  await p.setString(key, value);
    if (value is bool)    await p.setBool(key, value);
    if (value is int)     await p.setInt(key, value);
  }
}
