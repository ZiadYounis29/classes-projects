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
class FormatDropdown extends StatelessWidget {
  const FormatDropdown({
    super.key,
    required this.selected,
    required this.isAudioOnly,
    required this.onChanged,
    this.enabled = true,
  });

  final OutputFormat selected;
  final bool isAudioOnly;
  final ValueChanged<OutputFormat> onChanged;
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
            child: _FormatRow(format: f),
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
  const _FormatRow({required this.format});
  final OutputFormat format;

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
      ],
    );
  }
}
