import 'package:flutter/material.dart';

import '../controllers/download_queue_controller.dart';
import '../models/download_progress.dart';
import '../settings/app_settings.dart';

/// Batch download screen.
///
/// Paste multiple URLs (one per line) and download them all concurrently
/// using the shared [DownloadQueueController].
class BatchScreen extends StatefulWidget {
  const BatchScreen({super.key, required this.appSettings});
  final AppSettings appSettings;

  @override
  State<BatchScreen> createState() => _BatchScreenState();
}

class _BatchScreenState extends State<BatchScreen> {
  late final TextEditingController _urlsCtrl;
  DownloadQueueController? _queueCtrl;

  @override
  void initState() {
    super.initState();
    _urlsCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _urlsCtrl.dispose();
    _queueCtrl?.dispose();
    super.dispose();
  }

  void _onStart() {
    final text = _urlsCtrl.text.trim();
    if (text.isEmpty) return;
    FocusScope.of(context).unfocus();

    final urls = text
        .split(RegExp(r'[\n\r]+'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (urls.isEmpty) return;

    _queueCtrl?.dispose();
    _queueCtrl = DownloadQueueController(appSettings: widget.appSettings);
    _queueCtrl!.addUrls(urls);
    _queueCtrl!.addListener(_onQueueUpdate);
    _queueCtrl!.startAll();
    setState(() {});
  }

  void _onQueueUpdate() {
    if (mounted) setState(() {});
  }

  void _onReset() {
    _queueCtrl?.dispose();
    _queueCtrl = null;
    _urlsCtrl.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDownloading = _queueCtrl?.isRunning == true;
    final hasQueue = _queueCtrl != null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Text(
                'Batch download',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Paste a list of URLs (one per line) and download them all '
                'with the same settings. Concurrency limit comes from your '
                'Settings.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),

              // URL textarea
              if (!hasQueue) ...[
                TextField(
                  controller: _urlsCtrl,
                  enabled: !isDownloading,
                  maxLines: 8,
                  keyboardType: TextInputType.multiline,
                  decoration: const InputDecoration(
                    labelText: 'URLs (one per line)',
                    hintText:
                        'https://youtube.com/watch?v=...\nhttps://tiktok.com/...',
                    alignLabelWithHint: true,
                    prefixIcon: Padding(
                      padding: EdgeInsets.only(bottom: 140),
                      child: Icon(Icons.dynamic_feed),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: _onStart,
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Download all'),
                  ),
                ),
              ],

              // Queue progress
              if (hasQueue) ...[
                _BatchQueueSummary(
                  queue: _queueCtrl!,
                  onCancel: () => _queueCtrl!.cancelAll(),
                  onRetryFailed: () => _queueCtrl!.retryFailed(),
                  onReset: _onReset,
                ),
                const SizedBox(height: 8),
                _BatchQueueItems(queue: _queueCtrl!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _BatchQueueSummary extends StatelessWidget {
  const _BatchQueueSummary({
    required this.queue,
    required this.onCancel,
    required this.onRetryFailed,
    required this.onReset,
  });
  final DownloadQueueController queue;
  final VoidCallback onCancel;
  final VoidCallback onRetryFailed;
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
                    onPressed: onCancel,
                    icon: const Icon(Icons.close),
                    label: const Text('Cancel all'),
                  ),
                if (!queue.isRunning && errors > 0)
                  FilledButton.tonal(
                    onPressed: onRetryFailed,
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
                    label: const Text('New batch'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BatchQueueItems extends StatelessWidget {
  const _BatchQueueItems({required this.queue});
  final DownloadQueueController queue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final items = queue.items;

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
