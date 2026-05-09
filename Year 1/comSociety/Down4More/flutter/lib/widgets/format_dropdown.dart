import 'package:flutter/material.dart';

import '../models/output_format.dart';

/// Dropdown for choosing the output container/codec (MP4, MKV, MP3, etc.).
///
/// Shows only the formats relevant to the current quality selection:
/// - [isAudioOnly] = true  → audio formats only  (M4A, MP3, FLAC…)
/// - [isAudioOnly] = false → video formats only   (MP4, MKV, WebM)
///
/// When the quality switches categories (e.g. user picks "Audio only") the
/// controller automatically snaps [selected] to a sane default, so this
/// widget never shows an inconsistent state.
///
/// [sourceVideoBytes] is the [VideoFormat.fileSize] of the currently-selected
/// quality. [videoDuration] is the source video's runtime. Both are passed
/// through to [OutputFormat.estimateBytes] so each row can display an
/// approximate output size that updates live as the quality changes.
class FormatDropdown extends StatelessWidget {
  const FormatDropdown({
    super.key,
    required this.selected,
    required this.isAudioOnly,
    required this.onChanged,
    this.sourceVideoBytes,
    this.videoDuration,
    this.enabled = true,
  });

  final OutputFormat selected;
  final bool isAudioOnly;
  final ValueChanged<OutputFormat> onChanged;
  final int? sourceVideoBytes;
  final Duration? videoDuration;
  final bool enabled;

  List<OutputFormat> get _formats =>
      isAudioOnly ? kAudioFormats : kVideoFormats;

  @override
  Widget build(BuildContext context) {
    // Guard: if selected is from the wrong category (shouldn't happen thanks
    // to the controller snapping, but be defensive), fall back to the first
    // item in the list so the dropdown doesn't crash.
    final effectiveSelected = _formats.contains(selected)
        ? selected
        : _formats.first;

    return DropdownButtonFormField<String>(
      value: effectiveSelected.ext,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Format',
        prefixIcon: Icon(
          isAudioOnly ? Icons.audiotrack_outlined : Icons.movie_outlined,
        ),
      ),
      items: [
        for (final f in _formats)
          DropdownMenuItem<String>(
            value: f.ext,
            child: _FormatRow(
              format: f,
              estimateBytes: f.estimateBytes(
                sourceVideoBytes: sourceVideoBytes,
                duration: videoDuration,
              ),
            ),
          ),
      ],
      onChanged: enabled
          ? (ext) {
              if (ext == null) return;
              final fmt = _formats.firstWhere((f) => f.ext == ext);
              onChanged(fmt);
            }
          : null,
    );
  }
}

class _FormatRow extends StatelessWidget {
  const _FormatRow({required this.format, required this.estimateBytes});
  final OutputFormat format;
  final int? estimateBytes;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        // Pill badge for the extension
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: scheme.secondaryContainer,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            format.ext.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: scheme.onSecondaryContainer,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            format.note ?? format.label,
            style: const TextStyle(fontSize: 13),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (estimateBytes != null) ...[
          const SizedBox(width: 8),
          Text(
            // Prefix with a tilde so the user reads this as an estimate;
            // output containers vary slightly and audio formats are
            // bitrate-based.
            '~${formatBytes(estimateBytes!)}',
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

/// Compact human-readable byte formatter shared with [QualityDropdown].
/// Public so other widgets that show file-size chips render the same way.
String formatBytes(int bytes) {
  const kb = 1024;
  const mb = 1024 * 1024;
  const gb = 1024 * 1024 * 1024;
  if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(1)} GB';
  if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(0)} MB';
  if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(0)} KB';
  return '$bytes B';
}
