import 'package:flutter/material.dart';

import '../models/video_metadata.dart';

/// Dropdown of curated qualities for a fetched video. Appears under the
/// metadata card.
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
    return DropdownButtonFormField<String>(
      value: selected?.id,
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
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
            _formatBytes(format.fileSize!),
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

String _formatBytes(int bytes) {
  const kb = 1024;
  const mb = 1024 * 1024;
  const gb = 1024 * 1024 * 1024;
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(1)} GB';
  if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(0)} MB';
  if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(0)} KB';
  return '$bytes B';
}
