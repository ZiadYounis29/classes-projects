import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum DownloadStatus { finished, failed, cancelled }

/// A single entry in the download history log.
@immutable
class HistoryEntry {
  const HistoryEntry({
    required this.id,
    required this.title,
    required this.url,
    required this.outputPath,
    required this.finishedAt,
    required this.quality,
    required this.outputExt,
    this.status = DownloadStatus.finished,
    this.errorMessage,
  });

  final String id;
  final String title;
  final String url;
  final String outputPath;
  final DateTime finishedAt;
  final String quality;
  final String outputExt;
  final DownloadStatus status;
  final String? errorMessage;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'url': url,
        'outputPath': outputPath,
        'finishedAt': finishedAt.toIso8601String(),
        'quality': quality,
        'outputExt': outputExt,
        'status': status.name,
        if (errorMessage != null) 'errorMessage': errorMessage,
      };

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
        id: j['id'] as String? ?? '',
        title: j['title'] as String? ?? '',
        url: j['url'] as String? ?? '',
        outputPath: j['outputPath'] as String? ?? '',
        finishedAt: DateTime.tryParse(j['finishedAt'] as String? ?? '') ??
            DateTime.now(),
        quality: j['quality'] as String? ?? '',
        outputExt: j['outputExt'] as String? ?? '',
        status: DownloadStatus.values.firstWhere(
          (s) => s.name == (j['status'] as String? ?? ''),
          orElse: () => DownloadStatus.finished,
        ),
        errorMessage: j['errorMessage'] as String?,
      );
}

/// Persists a chronological log of completed downloads.
///
/// Backed by [SharedPreferences] under the key `d4m.history`.
/// Notifies listeners whenever the list changes.
///
/// Keep the list capped at [maxEntries] so SharedPreferences never bloats.
class DownloadHistory extends ChangeNotifier {
  DownloadHistory({SharedPreferences? prefs}) : _prefs = prefs;

  static const _kKey = 'd4m.history';
  static const int maxEntries = 500;

  SharedPreferences? _prefs;
  List<HistoryEntry> _entries = [];

  /// Most-recent first.
  List<HistoryEntry> get entries => List.unmodifiable(_entries);

  /// Load persisted history from disk. Call once at startup.
  Future<void> load() async {
    _prefs ??= await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_kKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      _entries = list
          .map((e) => HistoryEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      _entries = [];
    }
    notifyListeners();
  }

  /// Add a new entry (newest first). Trims to [maxEntries] automatically.
  Future<void> add(HistoryEntry entry) async {
    _entries.insert(0, entry);
    if (_entries.length > maxEntries) {
      _entries = _entries.sublist(0, maxEntries);
    }
    notifyListeners();
    await _persist();
  }

  /// Remove a single entry by id.
  Future<void> remove(String id) async {
    _entries.removeWhere((e) => e.id == id);
    notifyListeners();
    await _persist();
  }

  /// Wipe the entire history.
  Future<void> clear() async {
    _entries = [];
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    _prefs ??= await SharedPreferences.getInstance();
    final json = jsonEncode(_entries.map((e) => e.toJson()).toList());
    await _prefs!.setString(_kKey, json);
  }
}
