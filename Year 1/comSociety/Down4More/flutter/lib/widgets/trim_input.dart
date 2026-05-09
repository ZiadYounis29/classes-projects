import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Expandable tile that lets the user optionally set a start and/or end time
/// for a video segment. When both fields are empty the trim is disabled and
/// the download proceeds as normal.
///
/// Calls [onChanged] whenever either field changes to a valid (or cleared)
/// value. [onChanged] receives (start, end) where either may be null.
class TrimInput extends StatefulWidget {
  const TrimInput({
    super.key,
    required this.onChanged,
    this.enabled = true,
    this.videoDuration,
  });

  /// Called whenever the parsed trim window changes. Both args are null when
  /// the fields are empty / invalid.
  final void Function(Duration? start, Duration? end) onChanged;

  final bool enabled;

  /// Total video duration — used to clamp and validate end time. May be null
  /// for live streams or when metadata didn't include it.
  final Duration? videoDuration;

  @override
  State<TrimInput> createState() => _TrimInputState();
}

class _TrimInputState extends State<TrimInput> {
  final _startController = TextEditingController();
  final _endController = TextEditingController();
  String? _startError;
  String? _endError;
  bool _expanded = false;

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    super.dispose();
  }

  void _onFieldChanged() {
    final start = _parse(_startController.text.trim());
    final end = _parse(_endController.text.trim());

    String? startErr;
    String? endErr;

    if (_startController.text.trim().isNotEmpty && start == null) {
      startErr = 'Use HH:MM:SS or MM:SS';
    }
    if (_endController.text.trim().isNotEmpty && end == null) {
      endErr = 'Use HH:MM:SS or MM:SS';
    }
    if (start != null && end != null && start >= end) {
      endErr = 'End must be after start';
    }
    if (end != null &&
        widget.videoDuration != null &&
        end > widget.videoDuration!) {
      endErr = 'Exceeds video length';
    }

    setState(() {
      _startError = startErr;
      _endError = endErr;
    });

    // Only fire the callback when both set values are valid (or cleared).
    final validStart = startErr == null ? start : null;
    final validEnd = endErr == null ? end : null;

    // Don't fire if there were validation errors on non-empty fields.
    final hasStartErr = startErr != null;
    final hasEndErr = endErr != null;
    if (!hasStartErr && !hasEndErr) {
      widget.onChanged(validStart, validEnd);
    }
  }

  void _clearStart() {
    _startController.clear();
    _onFieldChanged();
  }

  void _clearEnd() {
    _endController.clear();
    _onFieldChanged();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasTrim = _startController.text.trim().isNotEmpty ||
        _endController.text.trim().isNotEmpty;

    return Card(
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Column(
        children: [
          // ── Header row ──────────────────────────────────────────────────
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: widget.enabled
                ? () => setState(() => _expanded = !_expanded)
                : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    Icons.content_cut_rounded,
                    size: 18,
                    color: hasTrim ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Trim segment',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: hasTrim
                          ? scheme.primary
                          : scheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Show the current range as a hint when collapsed.
                  if (!_expanded && hasTrim)
                    Expanded(
                      child: Text(
                        _rangeSummary(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    )
                  else
                    Expanded(
                      child: Text(
                        'Optional — clip a specific segment',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),

          // ── Expanded fields ─────────────────────────────────────────────
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 1),
                  const SizedBox(height: 14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _TimeField(
                          controller: _startController,
                          label: 'Start time',
                          hint: '0:00',
                          errorText: _startError,
                          enabled: widget.enabled,
                          onChanged: (_) => _onFieldChanged(),
                          onClear: _clearStart,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _TimeField(
                          controller: _endController,
                          label: 'End time',
                          hint: widget.videoDuration != null
                              ? _formatDur(widget.videoDuration!)
                              : 'end',
                          errorText: _endError,
                          enabled: widget.enabled,
                          onChanged: (_) => _onFieldChanged(),
                          onClear: _clearEnd,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Leave blank to keep the original. '
                    'Requires ffmpeg on PATH.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _rangeSummary() {
    final s = _startController.text.trim();
    final e = _endController.text.trim();
    if (s.isNotEmpty && e.isNotEmpty) return '$s → $e';
    if (s.isNotEmpty) return 'from $s';
    if (e.isNotEmpty) return 'up to $e';
    return '';
  }
}

// ── Single time-input field ──────────────────────────────────────────────────

class _TimeField extends StatelessWidget {
  const _TimeField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.onChanged,
    required this.onClear,
    this.errorText,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final String? errorText;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      onChanged: onChanged,
      keyboardType: TextInputType.datetime,
      textInputAction: TextInputAction.next,
      inputFormatters: [
        // Allow digits and colons only.
        FilteringTextInputFormatter.allow(RegExp(r'[\d:]')),
        LengthLimitingTextInputFormatter(8), // HH:MM:SS
      ],
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        errorText: errorText,
        prefixIcon: const Icon(Icons.access_time_outlined, size: 18),
        suffixIcon: controller.text.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.close, size: 16),
                onPressed: enabled ? onClear : null,
                tooltip: 'Clear',
              )
            : null,
        // Tighter vertical padding so the fields sit compact inside the tile.
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
      ),
    );
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

/// Parse a user-typed time string into a [Duration].
/// Accepts: `SS`, `M:SS`, `MM:SS`, `H:MM:SS`, `HH:MM:SS`.
/// Returns null if the string is empty or unparseable.
Duration? _parse(String s) {
  if (s.isEmpty) return null;
  final parts = s.split(':');
  try {
    if (parts.length == 1) {
      final secs = int.parse(parts[0]);
      return Duration(seconds: secs);
    }
    if (parts.length == 2) {
      return Duration(
        minutes: int.parse(parts[0]),
        seconds: int.parse(parts[1]),
      );
    }
    if (parts.length == 3) {
      return Duration(
        hours: int.parse(parts[0]),
        minutes: int.parse(parts[1]),
        seconds: int.parse(parts[2]),
      );
    }
  } on FormatException {
    return null;
  }
  return null;
}

String _formatDur(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  if (h > 0) return '$h:$m:$s';
  return '${d.inMinutes}:$s';
}
