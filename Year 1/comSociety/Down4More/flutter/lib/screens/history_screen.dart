import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../services/download_backend.dart';
import '../services/download_backend_factory.dart';
import '../services/download_history.dart';

/// Displays the chronological download history log.
///
/// Each row shows the video title, quality/format, finish time, and offers
/// quick actions: open the file, open the containing folder, copy the URL,
/// or delete the entry from the log. Failed and cancelled entries are shown
/// with distinct styling and a re-download shortcut.
class HistoryScreen extends StatelessWidget {
  HistoryScreen({
    super.key,
    required this.history,
    this.onRetryUrl,
    DownloadBackend? backend,
  }) : backend = backend ?? createDefaultBackend();

  final DownloadHistory history;
  final void Function(String url)? onRetryUrl;

  /// Used for the per-row Open file / Open folder buttons. Defaults to the
  /// platform's [createDefaultBackend] selection — desktop uses
  /// `url_launcher`; Android uses the [YtDlpPlugin] MethodChannel which
  /// resolves MediaStore URIs so the receiving viewer can read the file.
  final DownloadBackend backend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ListenableBuilder(
      listenable: history,
      builder: (context, _) {
        final entries = history.entries;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Header ───────────────────────────────────────────────
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'History',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Your download history.',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (entries.isNotEmpty)
                        IconButton(
                          onPressed: () => _confirmClear(context),
                          icon: const Icon(Icons.delete_sweep_outlined),
                          tooltip: 'Clear all history',
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ── Empty state ──────────────────────────────────────────
                  if (entries.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          children: [
                            Icon(Icons.history,
                                size: 48, color: scheme.onSurfaceVariant),
                            const SizedBox(height: 12),
                            Text(
                              'No history yet',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Completed, failed, and cancelled downloads will appear here.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // ── Entry list ───────────────────────────────────────────
                  for (final entry in entries)
                    _HistoryRow(
                      entry: entry,
                      onOpenFile: () => _openFile(context, entry.outputPath),
                      onOpenFolder: () =>
                          _openFolder(context, entry.outputPath),
                      onDelete: () => history.remove(entry.id),
                      onCopyUrl: entry.url.isNotEmpty
                          ? () => _copyUrl(context, entry.url)
                          : null,
                      onRedownload: entry.url.isNotEmpty &&
                              entry.status != DownloadStatus.finished
                          ? () => onRetryUrl?.call(entry.url)
                          : null,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _copyUrl(BuildContext context, String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('URL copied to clipboard'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _openFile(BuildContext context, String path) async {
    if (!await backend.openFile(path)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't open the file.")),
        );
      }
    }
  }

  Future<void> _openFolder(BuildContext context, String path) async {
    if (!await backend.openFolder(path)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't open the folder.")),
        );
      }
    }
  }

  Future<void> _confirmClear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all history?'),
        content: const Text(
          'This removes all entries from the log. '
          'Your downloaded files on disk are not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true) await history.clear();
  }
}

// ── Single history row ────────────────────────────────────────────────────────

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.entry,
    required this.onOpenFile,
    required this.onOpenFolder,
    required this.onDelete,
    this.onCopyUrl,
    this.onRedownload,
  });

  final HistoryEntry entry;
  final VoidCallback onOpenFile;
  final VoidCallback onOpenFolder;
  final VoidCallback onDelete;
  final VoidCallback? onCopyUrl;
  final VoidCallback? onRedownload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final isFailed    = entry.status == DownloadStatus.failed;
    final isCancelled = entry.status == DownloadStatus.cancelled;
    final isFinished  = entry.status == DownloadStatus.finished;

    // Dim the row if the file no longer exists on disk.
    final fileExists =
        entry.outputPath.isNotEmpty && File(entry.outputPath).existsSync();

    // Prefer the original video title (what the user pasted/searched for),
    // falling back to the saved filename when the metadata title was empty
    // (e.g. a failed fetch). The actual saved filename is surfaced in the
    // meta line below so users can still cross-reference it with disk.
    final filename = entry.outputPath.isNotEmpty
        ? p.basenameWithoutExtension(entry.outputPath)
        : '';
    final displayName = entry.title.trim().isNotEmpty
        ? entry.title.trim()
        : (filename.isNotEmpty ? filename : '(untitled)');

    // Icon and colour vary by status.
    final IconData rowIcon;
    final Color iconColor;
    if (isFailed) {
      rowIcon   = Icons.error_outline;
      iconColor = scheme.error;
    } else if (isCancelled) {
      rowIcon   = Icons.cancel_outlined;
      iconColor = scheme.onSurfaceVariant;
    } else {
      rowIcon   = _iconForExt(entry.outputExt);
      iconColor = fileExists ? scheme.primary : scheme.onSurfaceVariant;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      // Tint failed rows very slightly so they stand out at a glance.
      color: isFailed
          ? scheme.errorContainer.withValues(alpha: 0.25)
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(rowIcon, color: iconColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title / filename.
                      Text(
                        displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: isFailed
                              ? scheme.error
                              : (!isFinished || !fileExists)
                                  ? scheme.onSurfaceVariant
                                  : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      // Source URL.
                      if (entry.url.isNotEmpty)
                        Text(
                          entry.url,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.primary.withValues(alpha: 0.8),
                          ),
                        ),
                      const SizedBox(height: 2),
                      // Status badge · quality · format · date.
                      Text(
                        _meta(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isFailed
                              ? scheme.error.withValues(alpha: 0.8)
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                // ── Action buttons ───────────────────────────────────────
                if (isFinished && fileExists) ...[
                  IconButton(
                    onPressed: onOpenFile,
                    icon: const Icon(Icons.play_circle_outline),
                    tooltip: 'Open file',
                    iconSize: 20,
                  ),
                  IconButton(
                    onPressed: onOpenFolder,
                    icon: const Icon(Icons.folder_open_outlined),
                    tooltip: 'Show in folder',
                    iconSize: 20,
                  ),
                ],
                if (onRedownload != null)
                  IconButton(
                    onPressed: onRedownload,
                    icon: const Icon(Icons.replay_outlined),
                    tooltip: 'Retry in Single screen',
                    iconSize: 20,
                    color: isFailed ? scheme.error : null,
                  ),
                if (onCopyUrl != null)
                  IconButton(
                    onPressed: onCopyUrl,
                    icon: const Icon(Icons.link),
                    tooltip: 'Copy URL',
                    iconSize: 20,
                  ),
                IconButton(
                  onPressed: onDelete,
                  icon: Icon(Icons.delete_outline, color: scheme.error),
                  tooltip: 'Remove from history',
                  iconSize: 20,
                ),
              ],
            ),
            // ── Error message (failed only) ──────────────────────────────
            if (isFailed && entry.errorMessage != null && entry.errorMessage!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: scheme.errorContainer.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  entry.errorMessage!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onErrorContainer,
                    fontFamily: 'monospace',
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _meta() {
    final parts = <String>[];
    // Status badge for non-finished entries.
    if (entry.status == DownloadStatus.failed)    parts.add('FAILED');
    if (entry.status == DownloadStatus.cancelled) parts.add('CANCELLED');
    if (entry.quality.isNotEmpty)   parts.add(entry.quality);
    if (entry.outputExt.isNotEmpty) parts.add(entry.outputExt.toUpperCase());
    parts.add(_formatDate(entry.finishedAt));
    return parts.join('  ·  ');
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24)   return '${diff.inHours}h ago';
    if (diff.inDays < 7)     return '${diff.inDays}d ago';
    return '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)}';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  IconData _iconForExt(String ext) {
    if (['mp4', 'mkv', 'webm', 'avi', 'mov'].contains(ext)) {
      return Icons.movie_outlined;
    }
    if (['mp3', 'm4a', 'aac', 'ogg', 'opus', 'flac', 'wav'].contains(ext)) {
      return Icons.music_note_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }
}
