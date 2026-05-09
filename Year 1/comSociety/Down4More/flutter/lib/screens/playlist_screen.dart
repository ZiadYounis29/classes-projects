import 'package:flutter/material.dart';

import '../controllers/download_queue_controller.dart';
import '../controllers/playlist_controller.dart';
import '../models/output_format.dart';
import '../settings/app_settings.dart';
import '../widgets/queue_item_row.dart';

/// Playlist download screen.
///
/// Three phases:
///   1. URL input → Fetch
///   2. Selecting which entries to download (checkbox list)
///   3. Configuring + downloading the queue (per-item dropdowns,
///      per-item speed/size/cancel/retry, group-folder toggle)
class PlaylistScreen extends StatefulWidget {
  const PlaylistScreen({super.key, required this.appSettings});
  final AppSettings appSettings;

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  late final PlaylistController _playlistCtrl;
  late final TextEditingController _urlCtrl;
  late final TextEditingController _folderCtrl;
  DownloadQueueController? _queueCtrl;

  /// `true` once the user clicks "Start download". Distinguishes the
  /// configure stage (per-item dropdowns visible, no progress yet) from the
  /// running/done stage (progress bars + per-item cancel/retry visible).
  bool _started = false;

  /// Default output format applied to every queue item. Per-item dropdowns
  /// can override.
  OutputFormat _globalOutput = kDefaultVideoFormat;

  @override
  void initState() {
    super.initState();
    _playlistCtrl = PlaylistController();
    _urlCtrl = TextEditingController();
    _folderCtrl = TextEditingController();
    _globalOutput = _findFormat(widget.appSettings.defaultFormat);
  }

  OutputFormat _findFormat(String ext) {
    for (final f in [...kVideoFormats, ...kAudioFormats]) {
      if (f.ext == ext) return f;
    }
    return kDefaultVideoFormat;
  }

  @override
  void dispose() {
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
    await _playlistCtrl.fetchPlaylist(url);
  }

  void _onContinueWithSelected() {
    final entries = _playlistCtrl.selectedEntries;
    if (entries.isEmpty) return;

    _queueCtrl?.dispose();
    final q = DownloadQueueController(appSettings: widget.appSettings);
    q.addEntries(entries);
    q.setGlobalOutputFormat(_globalOutput);

    // Default group-folder ON for playlists, prefilled with playlist title.
    final folderName =
        _playlistCtrl.playlistTitle?.trim().isNotEmpty == true
            ? _playlistCtrl.playlistTitle!
            : 'Playlist';
    _folderCtrl.text = folderName;
    q.setGroupFolder(enabled: true, name: folderName);

    q.addListener(_onQueueUpdate);
    _queueCtrl = q;
    _started = false;
    setState(() {});
  }

  void _onStartDownload() {
    final q = _queueCtrl;
    if (q == null) return;
    q.setGroupFolder(enabled: q.groupFolderEnabled, name: _folderCtrl.text);
    _started = true;
    setState(() {});
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
    _urlCtrl.clear();
    _folderCtrl.clear();
    setState(() {});
  }

  void _onBackToSelect() {
    _queueCtrl?.dispose();
    _queueCtrl = null;
    _started = false;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _playlistCtrl,
      builder: (context, _) {
        final phase = _playlistCtrl.phase;
        final isFetching = phase == PlaylistPhase.fetching;
        final hasQueue = _queueCtrl != null;

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
                  _buildUrlRow(context, isFetching, hasQueue),
                  if (phase == PlaylistPhase.error) ...[
                    const SizedBox(height: 16),
                    _buildErrorBanner(context),
                  ],
                  if (phase == PlaylistPhase.ready && !hasQueue) ...[
                    const SizedBox(height: 16),
                    _buildSelectionBar(context),
                    const SizedBox(height: 8),
                    _buildEntryList(context),
                  ],
                  if (hasQueue) _buildQueueSection(context),
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
          'Paste a playlist URL, pick which videos you want, customize '
          'quality and format per video, then download them all at once.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildUrlRow(
      BuildContext context, bool isFetching, bool hasQueue) {
    final enabled = !isFetching && !hasQueue;
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

  Widget _buildSelectionBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = _playlistCtrl.entries.length;
    final selected = _playlistCtrl.selectedCount;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Text(
              '$selected of $total selected',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
            ),
            const Spacer(),
            TextButton(
              onPressed: selected == total
                  ? _playlistCtrl.deselectAll
                  : _playlistCtrl.selectAll,
              child: Text(selected == total ? 'Deselect all' : 'Select all'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: selected > 0 ? _onContinueWithSelected : null,
              icon: const Icon(Icons.arrow_forward),
              label: Text('Continue ($selected)'),
            ),
          ],
        ),
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

  Widget _buildQueueSection(BuildContext context) {
    final q = _queueCtrl!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        if (!_started)
          _ConfigureCard(
            queue: q,
            globalOutput: _globalOutput,
            onGlobalOutputChanged: (f) {
              setState(() => _globalOutput = f);
              q.setGlobalOutputFormat(f);
            },
            folderCtrl: _folderCtrl,
            onGroupFolderToggle: (v) {
              q.setGroupFolder(enabled: v, name: _folderCtrl.text);
            },
            onStartDownload: _onStartDownload,
            onBack: _onBackToSelect,
          )
        else
          _RunningCard(
            queue: q,
            onReset: _onReset,
          ),
        const SizedBox(height: 8),
        // Per-item rows.
        for (int i = 0; i < q.items.length; i++)
          _PreviewableRow(
            item: q.items[i],
            queue: q,
            index: i,
            // Lazy-fetch metadata for playlist items only when their card is
            // first built and the user hasn't started downloading yet. This
            // avoids hammering yt-dlp with N preview calls for huge playlists.
            autoPreview: !_started,
          ),
        if (!_started && q.items.isEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Queue is empty.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

/// Wraps [QueueItemRow] with auto-preview on first build (lazy fetch).
class _PreviewableRow extends StatefulWidget {
  const _PreviewableRow({
    required this.item,
    required this.queue,
    required this.index,
    required this.autoPreview,
  });

  final QueueItem item;
  final DownloadQueueController queue;
  final int index;
  final bool autoPreview;

  @override
  State<_PreviewableRow> createState() => _PreviewableRowState();
}

class _PreviewableRowState extends State<_PreviewableRow> {
  @override
  void initState() {
    super.initState();
    if (widget.autoPreview) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.queue.previewItem(widget.item);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return QueueItemRow(
      item: widget.item,
      queue: widget.queue,
      index: widget.index,
    );
  }
}

/// Card shown above the queue while the user is configuring (pre-start).
class _ConfigureCard extends StatelessWidget {
  const _ConfigureCard({
    required this.queue,
    required this.globalOutput,
    required this.onGlobalOutputChanged,
    required this.folderCtrl,
    required this.onGroupFolderToggle,
    required this.onStartDownload,
    required this.onBack,
  });

  final DownloadQueueController queue;
  final OutputFormat globalOutput;
  final ValueChanged<OutputFormat> onGlobalOutputChanged;
  final TextEditingController folderCtrl;
  final ValueChanged<bool> onGroupFolderToggle;
  final VoidCallback onStartDownload;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.tune, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Configure download (${queue.items.length} videos)',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Global format dropdown — applies to every item, but per-item
            // dropdowns can override.
            DropdownButtonFormField<String>(
              isDense: true,
              value: globalOutput.ext,
              decoration: const InputDecoration(
                labelText: 'Default format for all videos',
                prefixIcon: Icon(Icons.movie_outlined),
              ),
              items: [
                for (final f in [...kVideoFormats, ...kAudioFormats])
                  DropdownMenuItem(value: f.ext, child: Text(f.label)),
              ],
              onChanged: (ext) {
                if (ext == null) return;
                final f = [...kVideoFormats, ...kAudioFormats]
                    .firstWhere((x) => x.ext == ext);
                onGlobalOutputChanged(f);
              },
            ),
            const SizedBox(height: 12),
            // Group-folder toggle.
            ListenableBuilder(
              listenable: queue,
              builder: (_, __) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: queue.groupFolderEnabled,
                    onChanged: onGroupFolderToggle,
                    title: const Text('Save into a subfolder'),
                    subtitle: Text(
                      queue.groupFolderEnabled
                          ? 'Files go into Down4More / <subfolder>'
                          : 'Files go directly into Down4More',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                  if (queue.groupFolderEnabled)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: TextField(
                        controller: folderCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Folder name',
                          isDense: true,
                          prefixIcon: Icon(Icons.folder_outlined),
                        ),
                        onChanged: (v) =>
                            queue.setGroupFolder(enabled: true, name: v),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton.icon(
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back to selection'),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: queue.items.isEmpty ? null : onStartDownload,
                  icon: const Icon(Icons.download_rounded),
                  label: Text('Start download (${queue.items.length})'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Card shown above the queue once download has started.
class _RunningCard extends StatelessWidget {
  const _RunningCard({required this.queue, required this.onReset});
  final DownloadQueueController queue;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final done = queue.finishedCount;
    final total = queue.totalCount;
    final errors = queue.errorCount;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  queue.isRunning
                      ? Icons.downloading_rounded
                      : Icons.check_circle_outline,
                  color: scheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  queue.isRunning
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
                if (queue.isRunning)
                  TextButton.icon(
                    onPressed: () => queue.cancelAll(),
                    icon: const Icon(Icons.close),
                    label: const Text('Cancel all'),
                  ),
                if (!queue.isRunning && errors > 0)
                  FilledButton.tonal(
                    onPressed: () => queue.retryFailed(),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.refresh, size: 18),
                        SizedBox(width: 6),
                        Text('Retry failed'),
                      ],
                    ),
                  ),
                if (!queue.isRunning)
                  TextButton.icon(
                    onPressed: onReset,
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('New playlist'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDuration(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  if (h > 0) return '$h:${two(m)}:${two(s)}';
  return '$m:${two(s)}';
}
