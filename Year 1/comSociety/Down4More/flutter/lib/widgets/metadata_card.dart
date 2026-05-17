import 'package:flutter/material.dart';

import '../models/video_metadata.dart';

/// Card shown after a successful metadata fetch. Thumbnail on the left,
/// title + uploader + duration on the right.
class MetadataCard extends StatelessWidget {
  const MetadataCard({super.key, required this.metadata});

  final VideoMetadata metadata;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 160,
                height: 90,
                child: metadata.thumbnailUrl != null
                    ? Image.network(
                        metadata.thumbnailUrl!,
                        fit: BoxFit.cover,
                        loadingBuilder: (ctx, child, progress) =>
                            progress == null
                                ? child
                                : Container(color: scheme.surfaceContainerHighest),
                        errorBuilder: (_, __, ___) =>
                            _ThumbFallback(scheme: scheme),
                      )
                    : _ThumbFallback(scheme: scheme),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    metadata.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  if (metadata.uploader.isNotEmpty)
                    Text(
                      metadata.uploader,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 6),
                  if (metadata.duration != null)
                    Row(
                      children: [
                        Icon(
                          Icons.schedule,
                          size: 14,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          formatDuration(metadata.duration!),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Format a [Duration] as `MM:SS` or `H:MM:SS`. Used by the metadata card
/// header and the download finished card.
String formatDuration(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  if (h > 0) return '$h:${two(m)}:${two(s)}';
  return '$m:${two(s)}';
}

class _ThumbFallback extends StatelessWidget {
  const _ThumbFallback({required this.scheme});
  final ColorScheme scheme;
  @override
  Widget build(BuildContext context) {
    return Container(
      color: scheme.surfaceContainerHighest,
      child: Icon(
        Icons.movie_outlined,
        size: 40,
        color: scheme.onSurfaceVariant,
      ),
    );
  }
}
