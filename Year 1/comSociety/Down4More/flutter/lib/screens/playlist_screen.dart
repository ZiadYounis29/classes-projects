import 'package:flutter/material.dart';

import '../controllers/download_queue_controller.dart';
import '../controllers/playlist_controller.dart';
import '../models/output_format.dart';
import '../models/subtitle_settings.dart';
import '../models/video_metadata.dart';
import '../services/download_history.dart';
import '../settings/app_settings.dart';
import '../widgets/queue_item_row.dart';
import '../widgets/format_dropdown.dart' show formatBytes;
import '../widgets/subtitle_input.dart';

/// Builds a synthetic [VideoMetadata] that merges the subtitle availability
/// of all fetched queue items. Used to populate the global [SubtitleInput]
/// with real track information.
///
/// Manual subtitle langs are the union across all items.
///
/// For auto-captions we expose a single synthetic sentinel entry
/// [kAutoOrigSentinel] ('auto-orig') when *any* item has an *-orig
/// auto-caption track. This sentinel is language-agnostic — at download
/// time [DownloadQueueController] resolves it per-item to the actual
/// *-orig lang code that item carries (e.g. 'en-orig', 'ar-orig').
/// Items that have no auto-caption track are silently skipped.
VideoMetadata? _mergedSubtitleMetadata(List<QueueItem> items) {
  final fetched = items.where((i) => i.metadata != null).toList();
  if (fetched.isEmpty) return null;

  final subtitleLangs = <String>{};
  bool anyHasOrigAuto = false;

  for (final item in fetched) {
    final m = item.metadata!;
    subtitleLangs.addAll(m.availableSubtitleLangs);
    if (m.availableAutoCaptionLangs.any((k) => k.endsWith('-orig'))) {
      anyHasOrigAuto = true;
    }
  }

  // Expose the sentinel only when at least one item actually has an -orig
  // track. The SubtitleInput widget treats it as a normal auto-caption code
  // and displays it as "Original language (auto)" via _autoLangLabel.
  final autoCaptionLangs = anyHasOrigAuto ? [kAutoOrigSentinel] : <String>[];

  return VideoMetadata(
    url: '',
    title: '',
    uploader: '',
    duration: null,
    thumbnailUrl: null,
    formats: const [],
    availableSubtitleLangs: (subtitleLangs.toList()..sort()),
    availableAutoCaptionLangs: autoCaptionLangs,
  );
}

/// Playlist download screen.
///
/// Three-stage flow:
///   1. **Selection** (`phase == PlaylistPhase.ready && _queueCtrl == null`):
///      paste a URL, hit Fetch, tick the videos to download, then Continue.
///      The card carries no quality / format / folder controls — those are
///      moved to the next stage so this stage is purely about *which* videos.
///   2. **Configure** (`_queueCtrl != null && !_started`): identical layout
///      to [BatchScreen]'s configure card. Eagerly previews each selected
///      entry so size chips show, exposes the global Quality + Format
///      pickers, the All-same / Per-video [QualityMode] toggle, and the
///      group-folder toggle. Per-item dropdowns appear inline on each row
///      when the user flips to [QualityMode.perItem].
///   3. **Running** (`_started == true`): per-item progress rows + global
///      cancel-all / retry-failed / new-playlist controls.
class PlaylistScreen extends StatefulWidget {
  const PlaylistScreen({super.key, required this.appSettings, this.history});
  final AppSettings appSettings;
  final DownloadHistory? history;

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  late final PlaylistController _playlistCtrl;
  late final TextEditingController _urlCtrl;
  late final TextEditingController _folderCtrl;
  DownloadQueueController? _queueCtrl;

  /// True while [DownloadQueueController.previewAll] is fetching metadata
  /// for every selected entry — the user has clicked Continue but the
  /// configure card hasn't finished filling in size chips yet.
  bool _previewing = false;

  /// True once [_onStartDownload] has been called and the queue is actively
  /// downloading. Hides the configure card and shows the running card.
  bool _started = false;

  /// Merged subtitle metadata computed once after previewAll() completes.
  /// Passed to the global SubtitleInput so it shows only real available tracks.
  VideoMetadata? _mergedMeta;

  /// Whether to save downloads into a named subfolder (default: true for
  /// playlists per [AppSettings.playlistFolder]).
  bool _groupFolderEnabled = true;

  /// Global output format applied to every queue item when in
  /// [QualityMode.global].
  OutputFormat _globalOutput = kDefaultVideoFormat;

  /// Global quality preset applied to every queue item when in
  /// [QualityMode.global]. null = Best available, positive int = max
  /// height, -1 = audio-only.
  int? _globalQualityHeight;

  @override
  void initState() {
    super.initState();
    _playlistCtrl = PlaylistController();
    _urlCtrl = TextEditingController();
    _folderCtrl = TextEditingController();
    _applySettingsDefaults();
    widget.appSettings.addListener(_onSettingsChanged);
  }

  void _onSettingsChanged() {
    if (!_started) {
      setState(_applySettingsDefaults);
    }
  }

  void _applySettingsDefaults() {
    _globalOutput = _findFormat(widget.appSettings.defaultFormat);
    _globalQualityHeight =
        _qualityHeightFromSettings(widget.appSettings.defaultQuality);
    if (_globalQualityHeight == -1 &&
        _globalOutput.category == OutputCategory.video) {
      _globalOutput = _findFormat(widget.appSettings.defaultAudioFormat);
    }
    _groupFolderEnabled = widget.appSettings.playlistFolder;
  }

  OutputFormat _findFormat(String ext) {
    for (final f in [...kVideoFormats, ...kAudioFormats]) {
      if (f.ext == ext) return f;
    }
    return kDefaultVideoFormat;
  }

  int? _qualityHeightFromSettings(String q) {
    switch (q) {
      case 'audio':
        return -1;
      case 'best':
        return null;
      default:
        final h = int.tryParse(q.replaceAll('p', ''));
        return h;
    }
  }

  @override
  void dispose() {
    widget.appSettings.removeListener(_onSettingsChanged);
    _urlCtrl.dispose();
    _folderCtrl.dispose();
    _playlistCtrl.dispose();
    _queueCtrl?.dispose();
    super.dispose();
  }

  Future<void> _onFetch() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) return;
    FocusScope.of(context).unfocus();
    _queueCtrl?.dispose();
    _queueCtrl = null;
    _started = false;
    _previewing = false;
    _folderCtrl.clear();
    await _playlistCtrl.fetchPlaylist(url);
    // Pre-populate the folder name with the playlist title once fetched.
    if (_playlistCtrl.playlistTitle?.trim().isNotEmpty == true) {
      _folderCtrl.text = _playlistCtrl.playlistTitle!.trim();
    } else {
      _folderCtrl.text = 'Playlist';
    }
    if (mounted) setState(() {});
  }

  /// Stage 1 → Stage 2: build the queue from the user's selection and run
  /// an eager preview pass so the configure card can show real size chips.
  Future<void> _onContinue() async {
    final entries = _playlistCtrl.selectedEntries;
    if (entries.isEmpty) return;

    _queueCtrl?.dispose();
    final q = DownloadQueueController(appSettings: widget.appSettings, history: widget.history);
    q.addEntries(entries);
    q.setGroupFolder(enabled: _groupFolderEnabled, name: _folderCtrl.text);
    // Seed the queue's global subtitle config from the user's saved
    // defaults, but keep `enabled: false` so subs are an opt-in per playlist.
    q.setGlobalSubtitles(SubtitleSettings(
      enabled: false,
      language: widget.appSettings.defaultSubtitleLang,
      format: widget.appSettings.defaultSubtitleFormat,
    ));
    q.addListener(_onQueueUpdate);
    _queueCtrl = q;
    _started = false;
    _previewing = true;
    setState(() {});

    // Eager preview: fetch full metadata for every selected entry so the
    // size chips and per-item dropdowns can render meaningful values
    // immediately, without waiting for the user to expand each row.
    await q.previewAll(concurrency: 2);
    if (!mounted) return;

    // Apply the global preset + format now that metadata is loaded so
    // size chips reflect the user's quality choice immediately.
    q.setGlobalQualityPreset(
      targetHeight: _globalQualityHeight == -1 ? null : _globalQualityHeight,
      audioOnly: _globalQualityHeight == -1,
    );
    q.setGlobalOutputFormat(_globalOutput);

    setState(() {
      _previewing = false;
      _mergedMeta = _mergedSubtitleMetadata(q.items);
    });
  }

  void _onBackToSelection() {
    _queueCtrl?.dispose();
    _queueCtrl = null;
    _started = false;
    _previewing = false;
    _mergedMeta = null;
    setState(() {});
  }

  void _onStartDownload() {
    final q = _queueCtrl;
    if (q == null) return;
    q.setGroupFolder(enabled: _groupFolderEnabled, name: _folderCtrl.text);
    q.setGlobalQualityPreset(
      targetHeight: _globalQualityHeight == -1 ? null : _globalQualityHeight,
      audioOnly: _globalQualityHeight == -1,
    );
    q.setGlobalOutputFormat(_globalOutput);
    setState(() => _started = true);
    q.startAll();
  }

  void _onQueueUpdate() {
    if (mounted) setState(() {});
  }

  void _onReset() {
    _playlistCtrl.reset();
    _queueCtrl?.dispose();
    _queueCtrl = null;
    _started = false;
    _previewing = false;
    _mergedMeta = null;
    _applySettingsDefaults();
    _urlCtrl.clear();
    _folderCtrl.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _playlistCtrl,
      builder: (context, _) {
        final phase = _playlistCtrl.phase;
        final isFetching = phase == PlaylistPhase.fetching;
        final inSelection =
            phase == PlaylistPhase.ready && _queueCtrl == null;
        final inConfigure = _queueCtrl != null && !_started;
        final inRunning = _started && _queueCtrl != null;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(context),
                  const SizedBox(height: 20),
                  // The URL bar only belongs to stage 1. Hide it once a
                  // queue exists so the configure / running card can own
                  // the full width.
                  if (_queueCtrl == null) _buildUrlRow(context, isFetching),
                  if (phase == PlaylistPhase.error) ...[
                    const SizedBox(height: 16),
                    _buildErrorBanner(context),
                  ],
                  if (inSelection) ...[
                    const SizedBox(height: 16),
                    _buildSelectionHeader(context),
                    const SizedBox(height: 12),
                    // Continue button sits directly above the list so the
                    // user doesn't have to scroll to the bottom of a long
                    // playlist to advance — it's always reachable in the
                    // first viewport and updates its label live with the
                    // selection count.
                    _buildContinueButton(context),
                    const SizedBox(height: 8),
                    _buildEntryList(context),
                  ],
                  if (inConfigure) ...[
                    const SizedBox(height: 16),
                    _buildConfigureCard(context),
                    const SizedBox(height: 8),
                    for (int i = 0; i < _queueCtrl!.items.length; i++)
                      QueueItemRow(
                        item: _queueCtrl!.items[i],
                        queue: _queueCtrl!,
                        index: i,
                      ),
                  ],
                  if (inRunning) _buildRunningSection(context),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Playlist',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Paste a playlist URL, pick which videos you want, then configure '
          'quality and format on the next page.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildUrlRow(BuildContext context, bool isFetching) {
    final enabled = !isFetching && !_started;
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _urlCtrl,
            enabled: enabled,
            onSubmitted: (_) => _onFetch(),
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.go,
            decoration: const InputDecoration(
              labelText: 'Playlist URL',
              hintText: 'https://youtube.com/playlist?list=...',
              prefixIcon: Icon(Icons.list_alt),
            ),
          ),
        ),
        const SizedBox(width: 12),
        FilledButton.icon(
          onPressed: enabled ? _onFetch : null,
          icon: isFetching
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.search),
          label: Text(isFetching ? 'Fetching...' : 'Fetch'),
        ),
      ],
    );
  }

  Widget _buildErrorBanner(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: scheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _playlistCtrl.errorMessage ?? 'Unknown error',
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
            TextButton(onPressed: _onFetch, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  // ── Stage 1: selection (URL + Fetch + checkbox list + Continue) ────────

  Widget _buildSelectionHeader(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final total = _playlistCtrl.entries.length;
    final selected = _playlistCtrl.selectedCount;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Text(
              '$selected of $total selected',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: selected == total
                  ? _playlistCtrl.deselectAll
                  : _playlistCtrl.selectAll,
              child:
                  Text(selected == total ? 'Deselect all' : 'Select all'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContinueButton(BuildContext context) {
    final selected = _playlistCtrl.selectedCount;
    return Align(
      alignment: Alignment.centerRight,
      child: FilledButton.icon(
        onPressed: selected > 0 ? _onContinue : null,
        icon: const Icon(Icons.arrow_forward),
        label: Text('Continue ($selected)'),
      ),
    );
  }

  Widget _buildEntryList(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final entries = _playlistCtrl.entries;
    final selectedIndices = _playlistCtrl.selectedIndices;

    return Column(
      children: [
        for (int i = 0; i < entries.length; i++)
          Card(
            margin: const EdgeInsets.only(bottom: 4),
            child: InkWell(
              onTap: () => _playlistCtrl.toggleSelection(i),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Checkbox(
                      value: selectedIndices.contains(i),
                      onChanged: (_) => _playlistCtrl.toggleSelection(i),
                    ),
                    const SizedBox(width: 8),
                    if (entries[i].thumbnailUrl != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.network(
                          entries[i].thumbnailUrl!,
                          width: 80,
                          height: 45,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 80,
                            height: 45,
                            color: scheme.surfaceContainerHighest,
                            child: Icon(Icons.movie_outlined,
                                color: scheme.onSurfaceVariant),
                          ),
                        ),
                      )
                    else
                      Container(
                        width: 80,
                        height: 45,
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(Icons.movie_outlined,
                            color: scheme.onSurfaceVariant),
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entries[i].title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (entries[i].duration != null)
                            Text(
                              _formatDuration(entries[i].duration!),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      '#${i + 1}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ── Stage 2: configure (mode toggle + global pickers + folder + start) ─

  Widget _buildConfigureCard(BuildContext context) {
    final q = _queueCtrl!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final total = q.items.length;
    final previewed = q.items
        .where((i) => i.metadata != null || i.previewError != null)
        .length;

    final totalBytes = q.items.fold<int>(0, (sum, item) {
      final fmt = item.selectedOutputFormat ?? _globalOutput;
      final estimated = fmt.estimateBytes(
        sourceVideoBytes: item.selectedFormat?.fileSize,
        sourceAudioBytes: item.metadata?.audioOnlyFormat?.fileSize,
        duration: item.metadata?.duration,
      );
      return sum + (estimated ?? 0);
    });
    final totalSizeLabel = totalBytes > 0 ? '~${formatBytes(totalBytes)}' : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  _previewing ? Icons.hourglass_top : Icons.tune,
                  color: scheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _previewing
                        ? 'Previewing ($previewed / $total)…'
                        : 'Configure download ($total videos)',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            if (_previewing) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: total > 0 ? previewed / total : null,
                  minHeight: 4,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ),
            ],
            const SizedBox(height: 12),
            // ── Mode toggle (global vs per-item) ─────────────────────────
            ListenableBuilder(
              listenable: q,
              builder: (_, __) => _ModeToggle(
                mode: q.qualityMode,
                onChanged: (mode) {
                  q.setQualityMode(mode);
                  if (mode == QualityMode.global) {
                    q.setGlobalOutputFormat(_globalOutput);
                  }
                },
              ),
            ),
            const SizedBox(height: 12),
            // ── Global pickers ─ only when mode == global ────────────────
            ListenableBuilder(
              listenable: q,
              builder: (_, __) {
                if (q.qualityMode != QualityMode.global) {
                  return const SizedBox.shrink();
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _GlobalQualityPicker(
                      selectedHeight: _globalQualityHeight,
                      onChanged: (h) {
                        setState(() {
                          _globalQualityHeight = h;
                          if (h == -1 &&
                              _globalOutput.category ==
                                  OutputCategory.video) {
                            _globalOutput = _findFormat(
                                widget.appSettings.defaultAudioFormat);
                          } else if (h != -1 &&
                              _globalOutput.category ==
                                  OutputCategory.audio) {
                            _globalOutput = _findFormat(
                                widget.appSettings.defaultFormat);
                          }
                        });
                        q.setGlobalQualityPreset(
                          targetHeight: h == -1 ? null : h,
                          audioOnly: h == -1,
                        );
                        q.setGlobalOutputFormat(_globalOutput);
                      },
                    ),
                    const SizedBox(height: 12),
                    _GlobalFormatPicker(
                      globalOutput: _globalOutput,
                      isAudioOnly: _globalQualityHeight == -1,
                      onChanged: (f) {
                        setState(() => _globalOutput = f);
                        q.setGlobalOutputFormat(f);
                      },
                    ),
                    const SizedBox(height: 12),
                    SubtitleInput(
                      value: q.globalSubtitles,
                      outputFormat: _globalOutput,
                      metadata: _mergedMeta,
                      onChanged: q.setGlobalSubtitles,
                    ),
                    const SizedBox(height: 12),
                  ],
                );
              },
            ),
            // ── Folder ──────────────────────────────────────────────────
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _groupFolderEnabled,
              onChanged: (v) {
                setState(() => _groupFolderEnabled = v);
                q.setGroupFolder(enabled: v, name: _folderCtrl.text);
              },
              title: const Text('Save into a subfolder'),
              subtitle: Text(
                _groupFolderEnabled
                    ? 'Files go into Down4More / <subfolder>'
                    : 'Files go directly into Down4More',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              visualDensity: VisualDensity.compact,
            ),
            if (_groupFolderEnabled) ...[
              const SizedBox(height: 6),
              TextField(
                controller: _folderCtrl,
                decoration: const InputDecoration(
                  labelText: 'Folder name',
                  isDense: true,
                  prefixIcon: Icon(Icons.folder_outlined),
                ),
                onChanged: (v) =>
                    q.setGroupFolder(enabled: true, name: v),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _onBackToSelection,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back to selection'),
                ),
                const Spacer(),
                if (totalSizeLabel != null) ...[
                  Text(
                    totalSizeLabel,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                FilledButton.icon(
                  onPressed:
                      _previewing || total == 0 ? null : _onStartDownload,
                  icon: const Icon(Icons.download_rounded),
                  label: Text('Download $total items'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Stage 3: running ────────────────────────────────────────────────────

  Widget _buildRunningSection(BuildContext context) {
    final q = _queueCtrl!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ListenableBuilder(
      listenable: q,
      builder: (context, _) {
        final done = q.finishedCount;
        final total = q.totalCount;
        final errors = q.errorCount;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          q.isRunning
                              ? Icons.downloading_rounded
                              : Icons.check_circle_outline,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          q.isRunning
                              ? 'Downloading ($done / $total)...'
                              : 'Finished ($done / $total)',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (errors > 0) ...[
                          const SizedBox(width: 8),
                          Chip(
                            label: Text('$errors failed'),
                            backgroundColor: scheme.errorContainer,
                            side: BorderSide.none,
                            visualDensity: VisualDensity.compact,
                            labelStyle: TextStyle(
                              color: scheme.onErrorContainer,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: total > 0 ? done / total : null,
                        minHeight: 6,
                        backgroundColor: scheme.surfaceContainerHighest,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (q.isRunning) ...[
                          TextButton.icon(
                            onPressed: () => q.allPaused
                                ? q.resumeAll()
                                : q.pauseAll(),
                            icon: Icon(
                              q.allPaused
                                  ? Icons.play_arrow_rounded
                                  : Icons.pause_rounded,
                            ),
                            label: Text(
                                q.allPaused ? 'Resume all' : 'Pause all'),
                          ),
                          TextButton.icon(
                            onPressed: () => q.cancelAll(),
                            icon: const Icon(Icons.close),
                            label: const Text('Cancel all'),
                          ),
                        ],
                        if (!q.isRunning && errors > 0)
                          FilledButton.tonal(
                            onPressed: () => q.retryFailed(),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.refresh, size: 18),
                                SizedBox(width: 6),
                                Text('Retry failed'),
                              ],
                            ),
                          ),
                        if (!q.isRunning)
                          TextButton.icon(
                            onPressed: _onReset,
                            icon: const Icon(Icons.arrow_back),
                            label: const Text('New playlist'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            for (int i = 0; i < q.items.length; i++)
              QueueItemRow(item: q.items[i], queue: q, index: i),
          ],
        );
      },
    );
  }
}

// ── Mode toggle (global vs per-item) ─────────────────────────────────────────

/// SegmentedButton that flips the queue between [QualityMode.global] (a
/// single Quality + Format dropdown drives every row) and
/// [QualityMode.perItem] (each row exposes its own dropdowns).
///
/// Mirrors the toggle in [BatchScreen]; kept private to this file to avoid
/// promoting an internal widget into a shared file before there's a third
/// caller.
class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.mode, required this.onChanged});
  final QualityMode mode;
  final ValueChanged<QualityMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quality mode',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        SegmentedButton<QualityMode>(
          segments: const [
            ButtonSegment(
              value: QualityMode.global,
              icon: Icon(Icons.layers_outlined, size: 18),
              label: Text('All same'),
            ),
            ButtonSegment(
              value: QualityMode.perItem,
              icon: Icon(Icons.tune, size: 18),
              label: Text('Per video'),
            ),
          ],
          selected: {mode},
          onSelectionChanged: (s) => onChanged(s.first),
          showSelectedIcon: false,
        ),
      ],
    );
  }
}

// ── Global quality picker ─────────────────────────────────────────────────────

/// Quality presets expressed as max-height values.
/// null  = Best available
/// -1    = Audio only
const _kQualityPresets = [
  (label: 'Best available', height: null),
  (label: '4K (2160p)', height: 2160),
  (label: '1440p', height: 1440),
  (label: '1080p', height: 1080),
  (label: '720p', height: 720),
  (label: '480p', height: 480),
  (label: '360p', height: 360),
  (label: '240p', height: 240),
  (label: '144p', height: 144),
  (label: 'Audio only', height: -1),
];

class _GlobalQualityPicker extends StatelessWidget {
  const _GlobalQualityPicker({
    required this.selectedHeight,
    required this.onChanged,
  });

  /// null = Best, -1 = Audio only, positive = max height.
  final int? selectedHeight;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final validHeights = _kQualityPresets.map((p) => p.height).toSet();
    final effectiveHeight =
        validHeights.contains(selectedHeight) ? selectedHeight : null;

    return DropdownButtonFormField<int?>(
      value: effectiveHeight,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Quality for all videos',
        prefixIcon: Icon(Icons.high_quality_outlined),
      ),
      items: [
        for (final preset in _kQualityPresets)
          DropdownMenuItem<int?>(
            value: preset.height,
            child: _QualityPresetRow(preset: preset, scheme: scheme),
          ),
      ],
      onChanged: (h) => onChanged(h),
    );
  }
}

class _QualityPresetRow extends StatelessWidget {
  const _QualityPresetRow({required this.preset, required this.scheme});
  final ({String label, int? height}) preset;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    IconData icon;
    if (preset.height == null) {
      icon = Icons.star_outlined;
    } else if (preset.height == -1) {
      icon = Icons.audiotrack_outlined;
    } else {
      icon = Icons.videocam_outlined;
    }

    return Row(
      children: [
        Icon(icon, size: 16, color: scheme.onSurfaceVariant),
        const SizedBox(width: 10),
        Text(preset.label),
      ],
    );
  }
}

// ── Global format picker ─────────────────────────────────────────────────────

class _GlobalFormatPicker extends StatelessWidget {
  const _GlobalFormatPicker({
    required this.globalOutput,
    required this.isAudioOnly,
    required this.onChanged,
  });

  final OutputFormat globalOutput;
  final bool isAudioOnly;
  final ValueChanged<OutputFormat> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final formats = isAudioOnly ? kAudioFormats : kVideoFormats;
    final effectiveSelected =
        formats.contains(globalOutput) ? globalOutput : formats.first;

    return DropdownButtonFormField<String>(
      value: effectiveSelected.ext,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Format for all videos',
        prefixIcon: Icon(
          isAudioOnly ? Icons.audiotrack_outlined : Icons.movie_outlined,
        ),
      ),
      items: [
        for (final f in formats)
          DropdownMenuItem(
            value: f.ext,
            child: _FormatRow(format: f, scheme: scheme),
          ),
      ],
      onChanged: (ext) {
        if (ext == null) return;
        final f = formats.firstWhere((x) => x.ext == ext);
        onChanged(f);
      },
    );
  }
}

class _FormatRow extends StatelessWidget {
  const _FormatRow({required this.format, required this.scheme});
  final OutputFormat format;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: scheme.secondaryContainer,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            format.ext.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: scheme.onSecondaryContainer,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            format.note ?? format.label,
            style: const TextStyle(fontSize: 13),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

String _formatDuration(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  if (h > 0) return '$h:${two(m)}:${two(s)}';
  return '$m:${two(s)}';
}
