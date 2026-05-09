import 'package:flutter/material.dart';

import '../controllers/download_queue_controller.dart';
import '../controllers/playlist_controller.dart';
import '../models/download_progress.dart';
import '../settings/app_settings.dart';

/// Playlist download screen.
class PlaylistScreen extends StatefulWidget {
  const PlaylistScreen({super.key, required this.appSettings});
  final AppSettings appSettings;

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  late final PlaylistController _playlistCtrl;
  late final TextEditingController _urlCtrl;
  DownloadQueueController? _queueCtrl;

  @override
  void initState() {
    super.initState();
    _playlistCtrl = PlaylistController();
    _urlCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
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
    await _playlistCtrl.fetchPlaylist(url);
  }

  void _onDownloadSelected() {
    final entries = _playlistCtrl.selectedEntries;
    if (entries.isEmpty) return;

    _queueCtrl?.dispose();
    _queueCtrl = DownloadQueueController(appSettings: widget.appSettings);
    _queueCtrl!.addEntries(entries);
    _queueCtrl!.addListener(_onQueueUpdate);
    _queueCtrl!.startAll();
    setState(() {});
  }

  void _onQueueUpdate() {
    if (mounted) setState(() {});
  }

  void _onReset() {
    _playlistCtrl.reset();
    _queueCtrl?.dispose();
    _queueCtrl = null;
    _urlCtrl.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _playlistCtrl,
      builder: (context, _) {
        final phase = _playlistCtrl.phase;
        final isFetching = phase == PlaylistPhase.fetching;
        final isDownloading = _queueCtrl?.isRunning == true;

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
                  _buildUrlRow(context, isFetching, isDownloading),
                  if (phase == PlaylistPhase.error) ...[
                    const SizedBox(height: 16),
                    _buildErrorBanner(context),
                  ],
                  if (phase == PlaylistPhase.ready && _queueCtrl == null) ...[
                    const SizedBox(height: 16),
                    _buildSelectionBar(context),
                    const SizedBox(height: 8),
                    _buildEntryList(context),
                  ],
                  if (_queueCtrl != null) ...[
                    const SizedBox(height: 16),
                    _buildQueueSummary(context),
                    const SizedBox(height: 8),
                    _buildQueueItems(context),
                  ],
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
          'Paste a playlist URL, pick which videos you want, '
          'and download them all at once.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildUrlRow(
      BuildContext context, bool isFetching, bool isDownloading) {
    final enabled = !isFetching && !isDownloading;
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
              onPressed: selected > 0 ? _onDownloadSelected : null,
              icon: const Icon(Icons.download_rounded),
              label: Text('Download ($selected)'),
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

  Widget _buildQueueSummary(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final queue = _queueCtrl!;
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
                    onPressed: _onReset,
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

  Widget _buildQueueItems(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final items = _queueCtrl!.items;

    return Column(
      children: [
        for (int i = 0; i < items.length; i++)
          Card(
            margin: const EdgeInsets.only(bottom: 4),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  _phaseIcon(items[i].progress.phase, scheme),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          items[i].title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (items[i].progress.phase ==
                            DownloadPhase.downloading)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: items[i].progress.percent != null
                                    ? items[i].progress.percent! / 100
                                    : null,
                                minHeight: 4,
                                backgroundColor:
                                    scheme.surfaceContainerHighest,
                              ),
                            ),
                          ),
                        if (items[i].progress.phase == DownloadPhase.error &&
                            items[i].progress.errorMessage != null)
                          Text(
                            items[i].progress.errorMessage!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.error,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (items[i].progress.percent != null &&
                      items[i].progress.phase == DownloadPhase.downloading)
                    Text(
                      '${items[i].progress.percent!.toStringAsFixed(0)}%',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: scheme.primary,
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _phaseIcon(DownloadPhase phase, ColorScheme scheme) {
    switch (phase) {
      case DownloadPhase.idle:
        return Icon(Icons.hourglass_empty,
            size: 18, color: scheme.onSurfaceVariant);
      case DownloadPhase.fetchingMetadata:
      case DownloadPhase.downloading:
      case DownloadPhase.trimming:
        return SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: scheme.primary),
        );
      case DownloadPhase.ready:
        return Icon(Icons.download, size: 18, color: scheme.primary);
      case DownloadPhase.finished:
        return Icon(Icons.check_circle, size: 18, color: scheme.primary);
      case DownloadPhase.error:
        return Icon(Icons.error, size: 18, color: scheme.error);
      case DownloadPhase.cancelled:
        return Icon(Icons.cancel, size: 18, color: scheme.onSurfaceVariant);
    }
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
