import 'package:flutter/material.dart';

import '../models/download_progress.dart';

/// The mid-download / post-download view: progress bar + speed + ETA + cancel,
/// or success card with "Open file" / "Open folder", or error card with retry.
class DownloadProgressView extends StatelessWidget {
  const DownloadProgressView({
    super.key,
    required this.progress,
    required this.onCancel,
    required this.onOpenFile,
    required this.onOpenFolder,
    required this.onRetry,
    required this.onReset,
  });

  final DownloadProgress progress;
  final VoidCallback onCancel;
  final VoidCallback onOpenFile;
  final VoidCallback onOpenFolder;
  final VoidCallback onRetry;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    switch (progress.phase) {
      case DownloadPhase.downloading:
        return _DownloadingCard(progress: progress, onCancel: onCancel);
      case DownloadPhase.finished:
        return _FinishedCard(
          progress: progress,
          onOpenFile: onOpenFile,
          onOpenFolder: onOpenFolder,
          onReset: onReset,
        );
      case DownloadPhase.error:
        return _ErrorCard(progress: progress, onRetry: onRetry);
      case DownloadPhase.cancelled:
        return _CancelledCard(onRetry: onRetry, onReset: onReset);
      case DownloadPhase.idle:
      case DownloadPhase.fetchingMetadata:
      case DownloadPhase.ready:
        return const SizedBox.shrink();
    }
  }
}

class _DownloadingCard extends StatelessWidget {
  const _DownloadingCard({required this.progress, required this.onCancel});
  final DownloadProgress progress;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final pct = progress.percent;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.downloading, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  pct != null
                      ? 'Downloading… ${pct.toStringAsFixed(1)}%'
                      : 'Downloading…',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: onCancel,
                  icon: const Icon(Icons.close),
                  label: const Text('Cancel'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: pct != null ? pct / 100 : null,
                minHeight: 6,
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ),
            const SizedBox(height: 10),
            DefaultTextStyle.merge(
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              child: Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  if (progress.speedBytesPerSecond != null)
                    _StatChip(
                      icon: Icons.speed_outlined,
                      text: '${_formatBytes(progress.speedBytesPerSecond!.round())}/s',
                    ),
                  if (progress.eta != null)
                    _StatChip(
                      icon: Icons.schedule_outlined,
                      text: 'ETA ${_formatDuration(progress.eta!)}',
                    ),
                  if (progress.totalBytes != null)
                    _StatChip(
                      icon: Icons.save_alt_outlined,
                      text: _formatBytes(progress.totalBytes!),
                    ),
                ],
              ),
            ),
            if (progress.message != null) ...[
              const SizedBox(height: 8),
              Text(
                progress.message!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FinishedCard extends StatelessWidget {
  const _FinishedCard({
    required this.progress,
    required this.onOpenFile,
    required this.onOpenFolder,
    required this.onReset,
  });
  final DownloadProgress progress;
  final VoidCallback onOpenFile;
  final VoidCallback onOpenFolder;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle_outline, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Saved',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            if (progress.outputPath != null) ...[
              const SizedBox(height: 8),
              SelectableText(
                progress.outputPath!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: progress.outputPath != null ? onOpenFile : null,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Open file'),
                ),
                FilledButton.tonalIcon(
                  onPressed: progress.outputPath != null ? onOpenFolder : null,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Open folder'),
                ),
                TextButton.icon(
                  onPressed: onReset,
                  icon: const Icon(Icons.add),
                  label: const Text('New download'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.progress, required this.onRetry});
  final DownloadProgress progress;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline, color: scheme.onErrorContainer),
                const SizedBox(width: 8),
                Text(
                  'Something went wrong',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: scheme.onErrorContainer,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(
              progress.errorMessage ?? 'Unknown error',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onErrorContainer,
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CancelledCard extends StatelessWidget {
  const _CancelledCard({required this.onRetry, required this.onReset});
  final VoidCallback onRetry;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cancel_outlined, color: scheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Text(
                  'Cancelled',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              "We stopped the download. The partial file (if any) was left in"
              ' the destination folder for you to clean up.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.tonalIcon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
                TextButton.icon(
                  onPressed: onReset,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back to start'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: DefaultTextStyle.of(context).style.color),
        const SizedBox(width: 4),
        Text(text),
      ],
    );
  }
}

String _formatBytes(int bytes) {
  const kb = 1024;
  const mb = 1024 * 1024;
  const gb = 1024 * 1024 * 1024;
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(1)} GB';
  if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(1)} MB';
  if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(0)} KB';
  return '$bytes B';
}

String _formatDuration(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  if (h > 0) return '$h:${two(m)}:${two(s)}';
  return '$m:${two(s)}';
}
