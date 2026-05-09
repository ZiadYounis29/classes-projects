import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../controllers/download_queue_controller.dart';
import '../models/download_progress.dart';
import '../models/output_format.dart';
import 'format_dropdown.dart' show formatBytes;

/// One row in the Playlist / Batch queue list.
///
/// Renders the thumbnail + title, the per-item quality / format dropdowns
/// (when metadata is loaded), the live progress bar with speed + size, and
/// the contextual action buttons (Cancel / Retry / Open file / Open folder /
/// Remove). Used by both [PlaylistScreen] and [BatchScreen] so the two
/// surfaces stay visually consistent.
class QueueItemRow extends StatelessWidget {
  const QueueItemRow({
    super.key,
    required this.item,
    required this.queue,
    required this.index,
  });

  final QueueItem item;
  final DownloadQueueController queue;
  final int index;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final progress = item.progress;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildThumbnail(scheme),
                const SizedBox(width: 12),
                Expanded(child: _buildTitleAndStatus(theme, scheme)),
                if (progress.percent != null &&
                    progress.phase == DownloadPhase.downloading)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Text(
                      '${progress.percent!.toStringAsFixed(0)}%',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.primary,
                      ),
                    ),
                  ),
              ],
            ),

            // Per-item dropdowns when metadata is available + the item is
            // not actively downloading. Hidden during preview-fetch errors.
            if (item.metadata != null &&
                item.previewError == null &&
                progress.phase != DownloadPhase.downloading &&
                progress.phase != DownloadPhase.trimming) ...[
              const SizedBox(height: 10),
              _buildPerItemDropdowns(context),
            ],

            // Inline preview-fetch error.
            if (item.previewError != null) ...[
              const SizedBox(height: 8),
              _buildPreviewError(scheme, theme),
            ],

            const SizedBox(height: 8),
            _buildActionRow(context, scheme, theme),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnail(ColorScheme scheme) {
    final url = item.thumbnailUrl;
    if (url == null) {
      return Container(
        width: 80,
        height: 45,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(Icons.movie_outlined, color: scheme.onSurfaceVariant),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.network(
        url,
        width: 80,
        height: 45,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: 80,
          height: 45,
          color: scheme.surfaceContainerHighest,
          child: Icon(Icons.movie_outlined, color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }

  Widget _buildTitleAndStatus(ThemeData theme, ColorScheme scheme) {
    final progress = item.progress;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _PhaseIcon(phase: progress.phase, scheme: scheme),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        if (progress.phase == DownloadPhase.downloading) ...[
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress.percent != null ? progress.percent! / 100 : null,
              minHeight: 4,
              backgroundColor: scheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _formatStatusLine(progress),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ] else if (progress.phase == DownloadPhase.finished &&
            progress.outputPath != null) ...[
          const SizedBox(height: 2),
          Text(
            'Saved · ${progress.outputPath!.split(Platform.pathSeparator).last}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ] else if (progress.phase == DownloadPhase.error &&
            progress.errorMessage != null) ...[
          const SizedBox(height: 2),
          Text(
            progress.errorMessage!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
          ),
        ] else if (item.metadata?.duration != null) ...[
          const SizedBox(height: 2),
          Text(
            _formatDuration(item.metadata!.duration!),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }

  /// Compose `2.5 MB/s · 12 of 100 MB · ETA 0:39` style status string.
  String _formatStatusLine(DownloadProgress p) {
    final parts = <String>[];
    if (p.speedBytesPerSecond != null) {
      parts.add('${formatBytes(p.speedBytesPerSecond!.round())}/s');
    }
    if (p.totalBytes != null) {
      if (p.percent != null) {
        final done = (p.totalBytes! * (p.percent! / 100)).round();
        parts.add('${formatBytes(done)} / ${formatBytes(p.totalBytes!)}');
      } else {
        parts.add('of ${formatBytes(p.totalBytes!)}');
      }
    }
    if (p.eta != null) {
      parts.add('ETA ${_formatDuration(p.eta!)}');
    }
    if (parts.isEmpty) return p.message ?? 'Downloading…';
    return parts.join(' · ');
  }

  Widget _buildPerItemDropdowns(BuildContext context) {
    final theme = Theme.of(context);
    final m = item.metadata!;
    final selectedFormat = item.selectedFormat ?? m.formats.first;
    final selectedOutput = item.selectedOutputFormat ??
        (selectedFormat.isAudioOnly ? kDefaultAudioFormat : kDefaultVideoFormat);
    final formats =
        selectedFormat.isAudioOnly ? kAudioFormats : kVideoFormats;
    final outputBytes = selectedOutput.estimateBytes(
      sourceVideoBytes: selectedFormat.fileSize,
      duration: m.duration,
    );

    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        // Quality dropdown — compact form.
        // Width is 260 (was 220) and `isExpanded: true` so the selected
        // value plus its size suffix (e.g. `Best available · 301 MB`) lays
        // out inside the dropdown's content area instead of overflowing
        // past the trailing arrow. Without isExpanded the InputDecoration
        // sized the inner Row to its intrinsic width and hit a 160 px
        // constraint that clipped long labels with a yellow/black stripe.
        SizedBox(
          width: 260,
          child: DropdownButtonFormField<String>(
            isDense: true,
            isExpanded: true,
            value: selectedFormat.id,
            decoration: const InputDecoration(
              labelText: 'Quality',
              isDense: true,
              prefixIcon: Icon(Icons.high_quality_outlined, size: 18),
            ),
            items: [
              for (final f in m.formats)
                DropdownMenuItem(
                  value: f.id,
                  child: Text(
                    f.fileSize != null
                        ? '${f.label}  ·  ${formatBytes(f.fileSize!)}'
                        : f.label,
                    style: theme.textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (id) {
              if (id == null) return;
              final picked = m.formats.firstWhere((f) => f.id == id);
              queue.setItemFormat(item, picked);
              // If quality category changed (audio↔video) reset the output.
              if (picked.isAudioOnly !=
                      (item.selectedOutputFormat?.isAudio ?? false) &&
                  picked.isAudioOnly) {
                queue.setItemOutputFormat(item, kDefaultAudioFormat);
              } else if (!picked.isAudioOnly &&
                  (item.selectedOutputFormat?.isAudio ?? false)) {
                queue.setItemOutputFormat(item, kDefaultVideoFormat);
              }
            },
          ),
        ),
        // Format dropdown — compact form.
        SizedBox(
          width: 260,
          child: DropdownButtonFormField<String>(
            isDense: true,
            isExpanded: true,
            value: selectedOutput.ext,
            decoration: const InputDecoration(
              labelText: 'Format',
              isDense: true,
              prefixIcon: Icon(Icons.movie_outlined, size: 18),
            ),
            items: [
              for (final f in formats)
                DropdownMenuItem(
                  value: f.ext,
                  child: Text(
                    outputBytes != null && f.ext == selectedOutput.ext
                        ? '${f.label}  ·  ~${formatBytes(outputBytes)}'
                        : f.label,
                    style: theme.textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (ext) {
              if (ext == null) return;
              final picked = formats.firstWhere((f) => f.ext == ext);
              queue.setItemOutputFormat(item, picked);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPreviewError(ColorScheme scheme, ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 18, color: scheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              item.previewError!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onErrorContainer,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionRow(
      BuildContext context, ColorScheme scheme, ThemeData theme) {
    final progress = item.progress;
    final isActive = progress.phase == DownloadPhase.downloading ||
        progress.phase == DownloadPhase.trimming;
    final isFinished = progress.phase == DownloadPhase.finished;
    final isFailed = progress.phase == DownloadPhase.error ||
        progress.phase == DownloadPhase.cancelled;

    return Wrap(
      spacing: 4,
      runSpacing: 0,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (isActive)
          TextButton.icon(
            onPressed: () => queue.cancelItem(item),
            style: TextButton.styleFrom(
              foregroundColor: scheme.error,
              visualDensity: VisualDensity.compact,
            ),
            icon: const Icon(Icons.cancel_outlined, size: 16),
            label: const Text('Cancel'),
          ),
        if (isFailed)
          TextButton.icon(
            onPressed: () => queue.retryItem(item),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
            ),
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Retry'),
          ),
        if (isFinished && progress.outputPath != null) ...[
          TextButton.icon(
            onPressed: () => _openPath(context, progress.outputPath!),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            icon: const Icon(Icons.play_arrow_rounded, size: 16),
            label: const Text('Open'),
          ),
          TextButton.icon(
            onPressed: () => _openFolder(context, progress.outputPath!),
            style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            icon: const Icon(Icons.folder_open_outlined, size: 16),
            label: const Text('Folder'),
          ),
        ],
        if (!isActive && !isFinished)
          TextButton.icon(
            onPressed: () => queue.removeItem(item),
            style: TextButton.styleFrom(
              foregroundColor: scheme.onSurfaceVariant,
              visualDensity: VisualDensity.compact,
            ),
            icon: const Icon(Icons.close, size: 16),
            label: const Text('Remove'),
          ),
      ],
    );
  }

  Future<void> _openPath(BuildContext context, String path) async {
    final uri = Uri.file(path);
    if (!await launchUrl(uri) && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't open the file.")),
      );
    }
  }

  Future<void> _openFolder(BuildContext context, String path) async {
    final dir = File(path).parent.path;
    final uri = Uri.file(dir);
    if (!await launchUrl(uri) && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't open the folder.")),
      );
    }
  }
}

class _PhaseIcon extends StatelessWidget {
  const _PhaseIcon({required this.phase, required this.scheme});
  final DownloadPhase phase;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    switch (phase) {
      case DownloadPhase.idle:
        return Icon(Icons.hourglass_empty,
            size: 16, color: scheme.onSurfaceVariant);
      case DownloadPhase.fetchingMetadata:
      case DownloadPhase.downloading:
      case DownloadPhase.trimming:
        return SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: scheme.primary),
        );
      case DownloadPhase.ready:
        return Icon(Icons.download, size: 16, color: scheme.primary);
      case DownloadPhase.finished:
        return Icon(Icons.check_circle, size: 16, color: scheme.primary);
      case DownloadPhase.error:
        return Icon(Icons.error, size: 16, color: scheme.error);
      case DownloadPhase.cancelled:
        return Icon(Icons.cancel, size: 16, color: scheme.onSurfaceVariant);
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
