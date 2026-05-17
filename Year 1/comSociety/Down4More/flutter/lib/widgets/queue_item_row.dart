import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../controllers/download_queue_controller.dart';
import '../models/download_progress.dart';
import '../models/output_format.dart';
import 'format_dropdown.dart';
import 'quality_dropdown.dart';
import 'subtitle_input.dart';

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

            // Below-row info: in QualityMode.global this is just the size
            // chip (quality is shown by the global picker above the list);
            // in QualityMode.perItem we expand into Quality + Format
            // dropdowns next to the size chip so the user can override
            // each row independently. Per-item subtitle controls are
            // appended underneath in per-item mode so the user can pin a
            // different language/format/embed combo for each video.
            //
            // Controls are hidden once the queue is running — idle items
            // that are simply waiting for a concurrency slot have already
            // been committed and must not have their settings changed.
            if (item.metadata != null &&
                item.previewError == null &&
                !queue.isRunning &&
                progress.phase != DownloadPhase.downloading &&
                progress.phase != DownloadPhase.trimming &&
                progress.phase != DownloadPhase.finished &&
                progress.phase != DownloadPhase.error &&
                progress.phase != DownloadPhase.cancelled) ...[
              const SizedBox(height: 6),
              if (queue.qualityMode == QualityMode.perItem) ...[
                _buildPerItemControls(context),
                const SizedBox(height: 8),
                _buildPerItemSubtitles(context),
              ] else
                _buildQualityChip(context),
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

  Widget _buildQualityChip(BuildContext context) {
    final m = item.metadata!;
    if (m.formats.isEmpty) return const SizedBox.shrink();
    final selectedFormat = item.selectedFormat ?? m.formats.first;
    final selectedOutput = item.selectedOutputFormat ??
        (selectedFormat.isAudioOnly
            ? kDefaultAudioFormat
            : kDefaultVideoFormat);

    // Pick the size estimate based on BOTH resolution and output format.
    // For video formats this uses the source video's bytes × the format's
    // multiplier (≈1.0× for MP4/MKV, ≈0.95× for WebM); for audio formats
    // it uses bitrate × duration so swapping to MP3 / Opus / FLAC produces
    // a realistic estimate even though the source is a video stream.
    final estimated = selectedOutput.estimateBytes(
      sourceVideoBytes: selectedFormat.fileSize,
      duration: m.duration,
    );

    if (estimated == null) return const SizedBox.shrink();
    return _SizeChip(bytes: estimated);
  }

  /// Per-item Quality + Format dropdowns shown below the title row when the
  /// queue is in [QualityMode.perItem]. Each dropdown is wrapped in a
  /// fixed-width [SizedBox] (260px) so the labels and the size estimate
  /// fit without overflow at typical row widths — this is the same width
  /// chosen for the F3 fix from the PR #5 review. The size chip stays
  /// alongside so the user still sees the source bytes regardless of mode.
  Widget _buildPerItemControls(BuildContext context) {
    final m = item.metadata!;
    final formats = m.formats;
    if (formats.isEmpty) return _buildQualityChip(context);
    final selectedFormat = item.selectedFormat ?? formats.first;
    final selectedOutput = item.selectedOutputFormat ??
        (selectedFormat.isAudioOnly ? kDefaultAudioFormat : kDefaultVideoFormat);

    final estimated = selectedOutput.estimateBytes(
      sourceVideoBytes: selectedFormat.fileSize,
      duration: m.duration,
    );

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 260,
          child: QualityDropdown(
            formats: formats,
            selected: selectedFormat,
            onChanged: (f) => queue.setItemFormat(item, f),
          ),
        ),
        SizedBox(
          width: 260,
          child: FormatDropdown(
            selected: selectedOutput,
            isAudioOnly: selectedFormat.isAudioOnly,
            onChanged: (f) => queue.setItemOutputFormat(item, f),
            sourceVideoBytes: selectedFormat.fileSize,
            videoDuration: m.duration,
          ),
        ),
        if (estimated != null) _SizeChip(bytes: estimated),
      ],
    );
  }

  /// Compact per-item subtitle picker shown only in [QualityMode.perItem].
  ///
  /// The effective config = per-item override (if set) || the queue's
  /// [DownloadQueueController.globalSubtitles]. Any change is captured as a
  /// per-item override so the user can deviate from the global pick on a
  /// single row without disturbing the rest. Changing back to the exact
  /// global value still keeps the override — this is intentional, since
  /// otherwise toggling the master switch off would silently re-inherit
  /// the global "on" state.
  Widget _buildPerItemSubtitles(BuildContext context) {
    final m = item.metadata;
    if (m == null) return const SizedBox.shrink();
    final selectedFormat = item.selectedFormat ?? m.formats.first;
    final selectedOutput = item.selectedOutputFormat ??
        (selectedFormat.isAudioOnly
            ? kDefaultAudioFormat
            : kDefaultVideoFormat);

    final effective = item.subtitleSettings ?? queue.globalSubtitles;

    return SubtitleInput(
      value: effective,
      outputFormat: selectedOutput,
      metadata: item.metadata,
      compact: true,
      onChanged: (s) => queue.setItemSubtitleSettings(item, s),
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
    // Pause only applies while actively downloading (not trimming — ffmpeg
    // trim is fast and can't be meaningfully paused).
    final canPause = progress.phase == DownloadPhase.downloading;
    final isPaused = item.pauseRequested || (item.handle?.isPaused ?? false);

    return Wrap(
      spacing: 4,
      runSpacing: 0,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (canPause)
          _PauseResumeButton(
            isPaused: isPaused,
            onPressed: () => isPaused
                ? queue.resumeItem(item)
                : queue.pauseItem(item),
          ),
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

class _SizeChip extends StatelessWidget {
  const _SizeChip({required this.bytes});
  final int bytes;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        formatBytes(bytes),
        style: TextStyle(
          fontSize: 11,
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
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

/// Pause / Resume button used by the per-row action bar.
///
/// On Android the underlying yt-dlp library exposes no pause primitive, so
/// our [AndroidYtDlpBackend] fakes pause by cancelling the download and
/// re-issuing it with `--continue` on resume. That has visible
/// side-effects (speed/ETA reset, any in-progress merge restarts) that
/// users won't infer from a generic pause icon — so we surface them in a
/// tooltip on Android only.
class _PauseResumeButton extends StatelessWidget {
  const _PauseResumeButton({
    required this.isPaused,
    required this.onPressed,
  });

  final bool isPaused;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final button = TextButton.icon(
      onPressed: onPressed,
      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
      icon: Icon(
        isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
        size: 16,
      ),
      label: Text(isPaused ? 'Resume' : 'Pause'),
    );
    if (!Platform.isAndroid) return button;
    return Tooltip(
      message: isPaused
          ? 'Resuming on Android continues from the partial file.\n'
              'Speed and ETA reset until enough samples accumulate.'
          : 'On Android, pause stops yt-dlp and resumes from the partial\n'
              'file. Speed/ETA reset and any in-progress merge restarts.',
      waitDuration: const Duration(milliseconds: 300),
      child: button,
    );
  }
}
