import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/download_progress.dart';
import '../models/output_format.dart';
import '../models/video_metadata.dart';
import '../services/ytdlp_service.dart';
import '../settings/app_settings.dart';

/// Title strings yt-dlp returns from `--flat-playlist` when it has no real
/// title yet (Vimeo showcases especially). Used by [previewItem] and
/// [_startItem] to decide whether the row title should be replaced with the
/// real one once full metadata is fetched.
const Set<String> _kPlaceholderTitles = {'Unknown', 'Unknown title', 'NA'};

/// Quality / format selection mode for a queue.
///
/// - [global]: a single Quality + Format dropdown above the queue applies to
///   every item (lighter UI, but no per-item override).
/// - [perItem]: each row exposes its own Quality + Format dropdowns next to
///   the size chip (heavier UI, but matches the Single screen workflow).
///
/// Default is [QualityMode.global]. Settable via
/// [DownloadQueueController.setQualityMode]. The screens use this to swap
/// between the global picker card and the per-row dropdowns.
enum QualityMode { global, perItem }

/// One item in the download queue.
///
/// In the original PR-3 batch screen this only had [url], [title] and
/// [thumbnailUrl]. The Playlist + Batch parity work in this PR extends each
/// item with the metadata needed for per-item quality / format selection,
/// per-item progress, and per-item cancel / retry.
class QueueItem {
  QueueItem({
    required this.url,
    required this.title,
    this.thumbnailUrl,
  });

  final String url;
  String title;
  String? thumbnailUrl;

  /// Set by [DownloadQueueController.previewItem] once `--dump-single-json`
  /// has been fetched. `null` means we haven't tried yet (or fetch failed).
  VideoMetadata? metadata;

  /// Per-item quality override. When `null`, the queue uses a default
  /// `bv*+ba/b` selector. Once metadata is populated this typically tracks
  /// `metadata!.formats.first` ("Best available") until the user picks
  /// something else.
  VideoFormat? selectedFormat;

  /// Per-item output container/codec. When `null` falls back to
  /// [AppSettings.defaultFormat].
  OutputFormat? selectedOutputFormat;

  /// Error message from the preview pass, if any. Distinct from
  /// `progress.errorMessage` which only fires once a download has actually
  /// started.
  String? previewError;

  DownloadProgress progress = DownloadProgress.idle;
  DownloadHandle? handle;
  StreamSubscription<DownloadProgress>? subscription;
}

/// Manages a queue of downloads with configurable concurrency.
///
/// Used by both the Batch and Playlist screens. Each item starts as idle,
/// gets queued, downloads in parallel up to [AppSettings.concurrency],
/// and finishes / errors / cancels independently.
///
/// Quality + format selection follows the controller's [qualityMode]:
/// - [QualityMode.global] (default) drives every item via
///   [setGlobalQualityPreset] / [setGlobalOutputFormat].
/// - [QualityMode.perItem] lets each row override its own quality + format
///   via [setItemFormat] / [setItemOutputFormat].
///
/// Per-item metadata fetches go through [previewItem]. Group-folder support
/// is configured via [setGroupFolder].
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

  // ── Group-folder state ─────────────────────────────────────────────────
  bool _groupFolderEnabled = false;
  String _groupFolderName = '';

  // ── Stored quality preset (applied per-item when metadata is fetched) ──
  int? _qualityTargetHeight;   // null = best, positive = max height
  bool _qualityAudioOnly = false;

  // ── Quality selection mode (global vs per-item) ──
  QualityMode _qualityMode = QualityMode.global;

  bool get groupFolderEnabled => _groupFolderEnabled;
  String get groupFolderName => _groupFolderName;
  QualityMode get qualityMode => _qualityMode;

  /// Switch the queue between [QualityMode.global] and [QualityMode.perItem].
  ///
  /// When switching back to [QualityMode.global] we re-apply the most recent
  /// global preset so every row "snaps" to one quality — otherwise the rows
  /// would keep whatever the user last tweaked per-item, which is confusing
  /// when the per-item dropdowns disappear.
  void setQualityMode(QualityMode mode) {
    if (_qualityMode == mode) return;
    _qualityMode = mode;
    if (mode == QualityMode.global) {
      // Re-apply the stored preset so every row aligns with the global pick.
      for (final item in _items) {
        if (item.metadata == null) {
          item.selectedFormat = null;
        } else {
          _applyPresetToItem(item);
        }
      }
    }
    notifyListeners();
  }

  /// Configure the optional sub-folder all items will land in.
  ///
  /// Playlist screen calls this with `enabled: true` and the playlist title
  /// by default; the Batch screen calls it with `enabled: false` and a
  /// suggested name like `"<first item title> batch"`. Either side can flip
  /// the toggle / rename through the UI.
  void setGroupFolder({required bool enabled, String? name}) {
    _groupFolderEnabled = enabled;
    if (name != null) _groupFolderName = name;
    notifyListeners();
  }

  // ── Queue lifecycle ────────────────────────────────────────────────────

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

  /// `true` once every item has either finished, errored, cancelled,
  /// or hit a preview error. Used by the screens to swap the running
  /// indicator out for a "done" state.
  bool get allDone => _items.isNotEmpty && _items.every((i) {
        if (i.previewError != null) return true;
        return i.progress.phase == DownloadPhase.finished ||
            i.progress.phase == DownloadPhase.error ||
            i.progress.phase == DownloadPhase.cancelled;
      });

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
  void addEntries(
      List<({String url, String title, String? thumbnailUrl})> entries) {
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

  /// Retry every item that finished in error or cancelled state.
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

  // ── Per-item operations ────────────────────────────────────────────────

  /// Cancel one item without touching its siblings. Used by the per-row
  /// "Cancel" button in the Playlist + Batch screens.
  Future<void> cancelItem(QueueItem item) async {
    if (item.progress.phase == DownloadPhase.downloading ||
        item.progress.phase == DownloadPhase.trimming) {
      await item.handle?.cancel();
    } else if (item.progress.phase == DownloadPhase.idle) {
      item.progress =
          const DownloadProgress(phase: DownloadPhase.cancelled);
    }
    notifyListeners();
  }

  /// Reset one item to idle and re-enter the queue loop. Used by the
  /// per-row "Retry" button. If the queue isn't currently running we restart
  /// it so this single item gets picked up immediately.
  Future<void> retryItem(QueueItem item) async {
    if (item.progress.phase != DownloadPhase.error &&
        item.progress.phase != DownloadPhase.cancelled) {
      return;
    }
    item.progress = DownloadProgress.idle;
    item.handle = null;
    item.subscription = null;
    notifyListeners();
    if (!_running) {
      _running = true;
      notifyListeners();
      await _processQueue();
    }
  }

  /// Remove an item from the queue. Cancels it first if it's still active.
  Future<void> removeItem(QueueItem item) async {
    if (item.progress.phase == DownloadPhase.downloading ||
        item.progress.phase == DownloadPhase.trimming) {
      await item.handle?.cancel();
    }
    _items.remove(item);
    notifyListeners();
  }

  /// Override which curated quality to download for one item. When the user
  /// picks "1080p" on a single playlist entry the screen calls this; the
  /// next call to [_startItem] picks it up.
  ///
  /// If the new quality crosses the video↔audio category line we also snap
  /// [QueueItem.selectedOutputFormat] to a sane default for the new
  /// category (mp4 ↔ m4a). This mirrors the snap behaviour in
  /// [SingleDownloadController.selectFormat] so the per-item Format dropdown
  /// never shows a stale combination (e.g. "Audio only · MP4").
  void setItemFormat(QueueItem item, VideoFormat? format) {
    item.selectedFormat = format;
    if (format != null) {
      final out = item.selectedOutputFormat;
      if (out == null) {
        item.selectedOutputFormat =
            format.isAudioOnly ? kDefaultAudioFormat : kDefaultVideoFormat;
      } else if (format.isAudioOnly &&
          out.category == OutputCategory.video) {
        item.selectedOutputFormat = kDefaultAudioFormat;
      } else if (!format.isAudioOnly &&
          out.category == OutputCategory.audio) {
        item.selectedOutputFormat = kDefaultVideoFormat;
      }
    }
    notifyListeners();
  }

  /// Override which container/codec one item should land as.
  void setItemOutputFormat(QueueItem item, OutputFormat? format) {
    item.selectedOutputFormat = format;
    notifyListeners();
  }

  /// Apply a global quality override to every item. Used by the "Apply to
  /// all" dropdown above the queue.
  void setGlobalFormat(VideoFormat? format) {
    for (final item in _items) {
      item.selectedFormat = format;
    }
    notifyListeners();
  }

  /// Apply a global quality preset to every item by target height.
  ///
  /// [targetHeight] == null means "Best available".
  /// [audioOnly]   == true  means pick the audio-only format (lowest height).
  ///
  /// For each item that already has metadata we delegate to
  /// [_applyPresetToItem] (the same logic [_startItem] uses for items whose
  /// metadata arrives later). Items without metadata yet get
  /// [selectedFormat] = null so the queue falls back to the `bv*+ba/b`
  /// selector at download time — unless [_startItem] manages to fetch
  /// metadata first, in which case the preset is reapplied there.
  void setGlobalQualityPreset({int? targetHeight, bool audioOnly = false}) {
    // Persist so _startItem can apply it to items whose metadata isn't
    // available yet when this is called (e.g. playlist items before preview).
    _qualityTargetHeight = targetHeight;
    _qualityAudioOnly = audioOnly;

    for (final item in _items) {
      if (item.metadata == null) {
        item.selectedFormat = null;
        continue;
      }
      _applyPresetToItem(item);
    }
    notifyListeners();
  }

  /// Apply a global output-format override to every item.
  void setGlobalOutputFormat(OutputFormat? format) {
    for (final item in _items) {
      item.selectedOutputFormat = format;
    }
    notifyListeners();
  }

  /// Fetch full metadata for a single item via `yt-dlp --dump-single-json`.
  /// Used by:
  ///  - Playlist screen (lazy: only when user expands a row to customize it)
  ///  - Batch screen (eager: a "preview" pass that runs before the queue
  ///    starts so the user sees thumbnails + can pick per-item quality).
  ///
  /// On failure, sets [QueueItem.previewError] so the row can show the
  /// yt-dlp message inline. Does not throw.
  Future<void> previewItem(QueueItem item) async {
    if (item.metadata != null || item.previewError != null) return;
    try {
      final m = await _service.fetchMetadata(item.url);
      item.metadata = m;
      // Adopt richer info from yt-dlp into the row preview. The replace
      // guard has to cover three cases:
      //   1) initial title === url (set by addUrls when no title is known)
      //   2) empty / whitespace title
      //   3) flat-playlist placeholders ("Unknown", "Unknown title") that
      //      yt-dlp returns when the playlist preview lacks per-entry
      //      titles — common on Vimeo showcases.
      // Without case 3 the row title would stay as "Unknown" even after
      // the per-item preview has fetched the real title.
      final t = item.title.trim();
      if (t.isEmpty || t == item.url || _kPlaceholderTitles.contains(t)) {
        item.title = m.title;
      }
      item.thumbnailUrl ??= m.thumbnailUrl;
      item.selectedFormat ??= m.formats.first;
    } on YtDlpException catch (e) {
      item.previewError = e.message;
    } catch (e) {
      item.previewError = 'Unexpected error: $e';
    }
    notifyListeners();
  }

  /// Run [previewItem] across every item with bounded concurrency.
  /// Default is 2 — enough that a 50-video batch finishes the preview pass
  /// in under a minute on a normal connection without rate-limiting yt-dlp.
  Future<void> previewAll({int concurrency = 2}) async {
    final pending = _items.toList();
    final running = <Future<void>>[];

    while (pending.isNotEmpty || running.isNotEmpty) {
      while (pending.isNotEmpty && running.length < concurrency) {
        final next = pending.removeAt(0);
        final f = previewItem(next);
        running.add(f);
        f.whenComplete(() => running.remove(f));
      }
      if (running.isEmpty) break;
      await Future.any(running);
    }
  }

  // ── Internal queue loop ────────────────────────────────────────────────

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

  /// Apply the stored quality preset to one item that already has metadata.
  void _applyPresetToItem(QueueItem item) {
    final m = item.metadata;
    if (m == null) return;
    final formats = m.formats;
    if (formats.isEmpty) return;

    if (_qualityAudioOnly) {
      item.selectedFormat = formats.firstWhere(
        (f) => f.isAudioOnly,
        orElse: () => formats.last,
      );
      return;
    }
    if (_qualityTargetHeight == null) {
      item.selectedFormat = formats.first; // Best available
      return;
    }
    final candidates = formats
        .where((f) => f.height != null && f.height! <= _qualityTargetHeight!)
        .toList();
    if (candidates.isNotEmpty) {
      item.selectedFormat = candidates.first;
    } else {
      final withHeight = formats.where((f) => f.height != null).toList();
      item.selectedFormat =
          withHeight.isNotEmpty ? withHeight.last : formats.last;
    }
  }

  Future<void> _startItem(QueueItem item) async {
    final dir = await _resolveOutputDir();

    // If no format is selected yet and no metadata is available, fetch
    // metadata now and apply the stored quality preset. This handles the
    // playlist case where setGlobalQualityPreset is called before any
    // metadata is available (no preview pass), so items would otherwise all
    // fall back to 'bv*+ba/b' regardless of the user's quality pick.
    // We always fetch when metadata is missing so the quality chip shows
    // correctly in the UI and so 'best' gets an explicit selectedFormat too.
    if (item.selectedFormat == null && item.metadata == null) {
      try {
        final m = await _service.fetchMetadata(item.url);
        item.metadata = m;
        final t = item.title.trim();
        if (t.isEmpty || t == item.url || _kPlaceholderTitles.contains(t)) {
          item.title = m.title;
        }
        item.thumbnailUrl ??= m.thumbnailUrl;
        // Apply the stored preset to this item.
        _applyPresetToItem(item);
        notifyListeners();
      } catch (_) {
        // Metadata fetch failed — fall through to the bv*+ba/b fallback below.
      }
    }

    // Per-item override → fallback selector.
    final format = item.selectedFormat ??
        const VideoFormat(
          id: 'bv*+ba/b',
          label: 'Best available',
          ext: 'mp4',
          height: null,
          fileSize: null,
          note: null,
          isAudioOnly: false,
        );

    final rateLimit =
        _appSettings.hasSpeedLimit ? _appSettings.speedLimit : null;

    final outputExt =
        item.selectedOutputFormat?.ext ?? _appSettings.defaultFormat;

    item.handle = _service.download(
      // Prefer the richer metadata from a preview pass when we have it;
      // otherwise synthesise a minimal one from what addUrls/addEntries
      // gave us.
      metadata: item.metadata ??
          VideoMetadata(
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
      keepPartial: _appSettings.keepPartial,
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
          ? int.tryParse(RegExp(r'\(retry (\d+)')
                      .firstMatch(item.progress.errorMessage!)
                      ?.group(1) ??
                  '') ??
              0
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
    final String baseDir;
    if (custom.isNotEmpty) {
      baseDir = custom;
    } else {
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
      baseDir = p.join(base.path, 'Down4More');
    }

    String finalDir = baseDir;
    if (_groupFolderEnabled) {
      final folder = _sanitizeFolder(_groupFolderName);
      if (folder.isNotEmpty) {
        finalDir = p.join(baseDir, folder);
      }
    }

    final d = Directory(finalDir);
    if (!await d.exists()) await d.create(recursive: true);
    return finalDir;
  }

  /// Strip filesystem-unsafe characters from a folder name.
  String _sanitizeFolder(String name) {
    return name
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  @override
  void dispose() {
    cancelAll();
    super.dispose();
  }
}
