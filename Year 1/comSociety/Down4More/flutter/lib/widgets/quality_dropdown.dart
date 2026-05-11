import 'package:flutter/material.dart';

import '../models/video_metadata.dart';
import 'format_dropdown.dart' show formatBytes;

/// Dropdown of curated qualities for a fetched video. Appears under the
/// metadata card.
///
/// All qualities (video rungs + audio-only) are always shown so the user
/// can switch modes from either dropdown. The [FormatDropdown] handles
/// showing only formats relevant to the chosen quality category.
class QualityDropdown extends StatelessWidget {
  const QualityDropdown({
    super.key,
    required this.formats,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
  });

  final List<VideoFormat> formats;
  final VideoFormat? selected;
  final ValueChanged<VideoFormat> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    // Guard: if selected isn't in the list, fall back to first item.
    final effectiveSelected =
        formats.any((f) => f.id == selected?.id) ? selected : formats.firstOrNull;

    return DropdownButtonFormField<String>(
      value: effectiveSelected?.id,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Quality',
        prefixIcon: Icon(Icons.high_quality_outlined),
      ),
      items: [
        for (final f in formats)
          DropdownMenuItem<String>(
            value: f.id,
            child: _QualityRow(format: f),
          ),
      ],
      onChanged: enabled
          ? (id) {
              if (id == null) return;
              final f = formats.firstWhere((e) => e.id == id);
              onChanged(f);
            }
          : null,
    );
  }
}

class _QualityRow extends StatelessWidget {
  const _QualityRow({required this.format});
  final VideoFormat format;

  IconData get _icon {
    if (format.isAudioOnly) return Icons.audiotrack_outlined;
    if (format.height == null) return Icons.star_outlined; // "Best available"
    return Icons.videocam_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(_icon, size: 16, color: scheme.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            format.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (format.fileSize != null) ...[
          const SizedBox(width: 8),
          Text(
            formatBytes(format.fileSize!),
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }
}
