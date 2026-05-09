import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/download_progress.dart';
import '../models/video_metadata.dart';
import '../services/ytdlp_service.dart';
import '../settings/app_settings.dart';

/// One item in the download queue.
class QueueItem {
  QueueItem({
    required this.url,
    required this.title,
    this.thumbnailUrl,
  });

  final String url;
  final String title;
  final String? thumbnailUrl;

  DownloadProgress progress = DownloadProgress.idle;
  DownloadHandle? handle;
  StreamSubscription<DownloadProgress>? subscription;
}

/// Manages a queue of downloads with configurable concurrency.
///
/// Used by both the Batch and Playlist screens. Each item starts as idle,
/// gets queued, downloads in parallel up to [AppSettings.concurrency],
/// and finishes/errors/cancels independently.
class DownloadQueueController extends ChangeNotifier {
  DownloadQueueController({
    required AppSettings appSettings,
    YtDlpService? service,
  })  : _appSettings = appSettings,
        _service = service ?? YtDlpService();

  final AppSettings _appSettings;
  final YtDlpService _service;

  final List<QueueItem> _items = [];
  int _activeCount = 0;
  bool _running = false;

  List<QueueItem> get items => List.unmodifiable(_items);
  bool get isRunning => _running;
  int get totalCount => _items.length;
  int get finishedCount => _items
      .where((i) =>
          i.progress.phase == DownloadPhase.finished ||
          i.progress.phase == DownloadPhase.error ||
          i.progress.phase == DownloadPhase.cancelled)
      .length;
  int get errorCount =>
      _items.where((i) => i.progress.phase == DownloadPhase.error).length;

  /// Add URLs to the queue. Does not start downloading yet.
  void addUrls(List<String> urls) {
    for (final url in urls) {
      if (url.trim().isEmpty) continue;
      _items.add(QueueItem(
        url: url.trim(),
        title: url.trim(),
      ));
    }
    notifyListeners();
  }

  /// Add items with known titles (from playlist entries).
  void addEntries(List<({String url, String title, String? thumbnailUrl})> entries) {
    for (final e in entries) {
      if (e.url.trim().isEmpty) continue;
      _items.add(QueueItem(
        url: e.url.trim(),
        title: e.title,
        thumbnailUrl: e.thumbnailUrl,
      ));
    }
    notifyListeners();
  }

  /// Start processing the queue. Downloads up to [concurrency] items in
  /// parallel, picking the next idle item whenever a slot opens.
  Future<void> startAll() async {
    if (_running) return;
    _running = true;
    // Pre-create the output directory before any items start downloading.
    // This avoids race conditions where yt-dlp tries to rename a file into
    // a directory that hasn't been created yet.
    await _resolveOutputDir();
    notifyListeners();
    await _processQueue();
  }

  /// Cancel all running and pending downloads.
  Future<void> cancelAll() async {
    _running = false;
    for (final item in _items) {
      if (item.progress.phase == DownloadPhase.downloading ||
          item.progress.phase == DownloadPhase.trimming) {
        await item.handle?.cancel();
      } else if (item.progress.phase == DownloadPhase.idle) {
        item.progress =
            const DownloadProgress(phase: DownloadPhase.cancelled);
      }
    }
    notifyListeners();
  }

  /// Clear all items and reset.
  void clear() {
    cancelAll();
    _items.clear();
    _activeCount = 0;
    _running = false;
    notifyListeners();
  }

  /// Retry all failed items.
  Future<void> retryFailed() async {
    for (final item in _items) {
      if (item.progress.phase == DownloadPhase.error ||
          item.progress.phase == DownloadPhase.cancelled) {
        item.progress = DownloadProgress.idle;
        item.handle = null;
        item.subscription = null;
      }
    }
    notifyListeners();
    if (!_running) {
      _running = true;
      notifyListeners();
      await _processQueue();
    }
  }

  Future<void> _processQueue() async {
    final concurrency = _appSettings.concurrency;

    while (_running) {
      // Find the next idle item.
      final nextIdle = _items.cast<QueueItem?>().firstWhere(
        (i) => i!.progress.phase == DownloadPhase.idle,
        orElse: () => null,
      );

      if (nextIdle == null) {
        // No more idle items. Wait for active ones to finish or break.
        if (_activeCount == 0) break;
        await Future.delayed(const Duration(milliseconds: 200));
        continue;
      }

      if (_activeCount >= concurrency) {
        // Wait for a slot to open.
        await Future.delayed(const Duration(milliseconds: 200));
        continue;
      }

      // Mark as non-idle synchronously BEFORE the async _startItem runs,
      // so the loop won't pick up the same item again on the next iteration.
      _activeCount++;
      nextIdle.progress =
          const DownloadProgress(phase: DownloadPhase.downloading);
      notifyListeners();
      _startItem(nextIdle);
    }

    _running = false;
    notifyListeners();
  }

  Future<void> _startItem(QueueItem item) async {
    final dir = await _resolveOutputDir();

    // Use "best" quality with the user's default format.
    final format = const VideoFormat(
      id: 'bv*+ba/b',
      label: 'Best available',
      ext: 'mp4',
      height: null,
      fileSize: null,
      note: null,
      isAudioOnly: false,
    );

    final rateLimit = _appSettings.hasSpeedLimit
        ? _appSettings.speedLimit
        : null;

    final outputExt = _appSettings.defaultFormat;

    item.handle = _service.download(
      metadata: VideoMetadata(
        url: item.url,
        title: item.title,
        uploader: '',
        duration: null,
        thumbnailUrl: item.thumbnailUrl,
        formats: [format],
      ),
      format: format,
      outputDir: dir,
      outputExt: outputExt,
      rateLimit: rateLimit,
    );

    item.subscription = item.handle!.stream.listen(
      (event) {
        item.progress = event;
        notifyListeners();
      },
      onDone: () {
        _activeCount--;
        item.subscription = null;

        // Auto-retry on error if configured.
        final maxRetries = _appSettings.autoRetry;
        if (item.progress.phase == DownloadPhase.error && maxRetries > 0) {
          _retryItem(item, maxRetries);
        }

        notifyListeners();
      },
    );

    item.progress =
        const DownloadProgress(phase: DownloadPhase.downloading);
    notifyListeners();
  }

  int _retryCount(QueueItem item) =>
      item.progress.errorMessage?.contains('(retry') == true
          ? int.tryParse(RegExp(r'\(retry (\d+)').firstMatch(
                  item.progress.errorMessage!)?.group(1) ?? '') ?? 0
          : 0;

  Future<void> _retryItem(QueueItem item, int maxRetries) async {
    final attempt = _retryCount(item) + 1;
    if (attempt > maxRetries) return;

    await Future.delayed(Duration(seconds: _appSettings.retryDelay));
    if (!_running) return;

    item.progress = DownloadProgress.idle;
    notifyListeners();
  }

  Future<String> _resolveOutputDir() async {
    final custom = _appSettings.downloadDir;
    if (custom.isNotEmpty) {
      final d = Directory(custom);
      if (!await d.exists()) await d.create(recursive: true);
      return custom;
    }

    Directory? base;
    try {
      base = await getDownloadsDirectory();
    } catch (_) {
      base = null;
    }
    if (base == null) {
      final home = Platform.environment['HOME'] ??
          Platform.environment['USERPROFILE'];
      if (home != null) {
        base = Directory(p.join(home, 'Downloads'));
      } else {
        base = Directory.current;
      }
    }
    final dir = Directory(p.join(base.path, 'Down4More'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  @override
  void dispose() {
    cancelAll();
    super.dispose();
  }
}
