import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Expandable tile that lets the user optionally set a start and/or end time
/// for a video segment. When both fields are empty the trim is disabled and
/// the download proceeds as normal.
///
/// The fields use a "digit-shift" entry style: the user types raw digits and
/// the colons are inserted automatically. Typing `5 5 1 2` shows `55:12`
/// (55 min 12 s); typing one more digit shifts everything left to
/// `5:51:2x` → `5:51:20`. Backspace removes the rightmost digit.
///
/// Calls [onChanged] whenever either field changes to a valid (or cleared)
/// value. [onChanged] receives (start, end) where either may be null.
///
/// [onValidityChanged] is called whenever the trim error state changes — true
/// means there is at least one validation error currently shown (e.g. end
/// before start, exceeds duration). Use this to disable the download button.
class TrimInput extends StatefulWidget {
  const TrimInput({
    super.key,
    required this.onChanged,
    this.onValidityChanged,
    this.enabled = true,
    this.videoDuration,
  });

  /// Called whenever the parsed trim window changes. Both args are null when
  /// the fields are empty / invalid.
  final void Function(Duration? start, Duration? end) onChanged;

  /// Called whenever the error state changes. [hasError] is true when one or
  /// more fields are in an error state. Null when the caller doesn't care.
  final void Function(bool hasError)? onValidityChanged;

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

    // Format errors only fire when the user has typed something but the
    // digit-shift formatter somehow produced an unparseable string. In
    // practice this is unreachable, but we keep the check defensive.
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

    final hadError = (_startError != null || _endError != null);
    final hasError = (startErr != null || endErr != null);

    setState(() {
      _startError = startErr;
      _endError = endErr;
    });

    // Notify caller when validity flips so the download button can be gated.
    if (hasError != hadError) {
      widget.onValidityChanged?.call(hasError);
    }

    // Only fire the callback when both set values are valid (or cleared).
    final validStart = startErr == null ? start : null;
    final validEnd = endErr == null ? end : null;

    if (!hasError) {
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
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Trim segment',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: hasTrim ? scheme.primary : scheme.onSurface,
                          ),
                        ),
                        if (!_expanded || !hasTrim)
                          Text(
                            hasTrim
                                ? _rangeSummary()
                                : 'Optional — clip a specific segment',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
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
                        child: _DigitShiftField(
                          controller: _startController,
                          label: 'Start time',
                          hint: '0:00',
                          enabled: widget.enabled,
                          onChanged: (_) => _onFieldChanged(),
                          onClear: _clearStart,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _DigitShiftField(
                          controller: _endController,
                          label: 'End time',
                          hint: widget.videoDuration != null
                              ? _formatDur(widget.videoDuration!)
                              : 'end',
                          enabled: widget.enabled,
                          onChanged: (_) => _onFieldChanged(),
                          onClear: _clearEnd,
                        ),
                      ),
                    ],
                  ),

                  // ── Warning banners ──────────────────────────────────────
                  if (_startError != null) ...[
                    const SizedBox(height: 10),
                    _WarningBanner(
                      label: 'Start time',
                      message: _startError!,
                    ),
                  ],
                  if (_endError != null) ...[
                    const SizedBox(height: 10),
                    _WarningBanner(
                      label: 'End time',
                      message: _endError!,
                    ),
                  ],

                  const SizedBox(height: 10),
                  Text(
                    'Type digits — colons are inserted for you. '
                    'Leave blank to keep the original. Requires ffmpeg on PATH.',
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

class _WarningBanner extends StatelessWidget {
  const _WarningBanner({required this.label, required this.message});
  final String label;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: scheme.error.withValues(alpha: 0.65),
          width: 1.2,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 20,
            color: scheme.error,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onErrorContainer,
                ),
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: message),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A TextField that interprets user input as a sequence of digits and
/// formats them right-to-left into `S`, `M:SS`, `MM:SS`, `H:MM:SS`,
/// `HH:MM:SS`. Colons are inserted automatically. Backspace removes the
/// rightmost digit. The cursor is always pinned at the end.
class _DigitShiftField extends StatelessWidget {
  const _DigitShiftField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.onChanged,
    required this.onClear,
    this.enabled = true,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      onChanged: onChanged,
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.next,
      inputFormatters: const [DigitShiftFormatter()],
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
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

/// Strips non-digits, caps to 6 digits, then re-renders the time string with
/// auto-inserted colons. The cursor position is preserved relative to the
/// surrounding digits so that mid-field edits (delete-then-retype) feel
/// natural instead of snapping to the far right every keystroke.
@visibleForTesting
class DigitShiftFormatter extends TextInputFormatter {
  const DigitShiftFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final newText = newValue.text;
    final cursorOffset =
        newValue.selection.baseOffset.clamp(0, newText.length);

    // Count how many digit characters fall before the cursor in the raw
    // (pre-format) new value so we can map that position into the
    // formatted output.
    int digitsBeforeCursor = 0;
    for (int i = 0; i < cursorOffset; i++) {
      if (_isDigit(newText[i])) digitsBeforeCursor++;
    }

    final raw = newText.replaceAll(RegExp(r'[^0-9]'), '');
    // Drop leading padding zeros so the digit count tracks real keystrokes.
    final stripped = raw.replaceFirst(RegExp(r'^0+'), '');
    final capped = stripped.length > 6
        ? stripped.substring(stripped.length - 6)
        : stripped;
    final formatted = formatDigitsAsTime(capped);

    // How many leading zeros were stripped from the raw digits?
    final zerosStripped = raw.length - stripped.length;
    final adjustedDigits =
        (digitsBeforeCursor - zerosStripped).clamp(0, capped.length);

    // Padding zeros the formatter may have prepended (e.g. "5" → "0:05").
    int formattedDigitCount = 0;
    for (int i = 0; i < formatted.length; i++) {
      if (_isDigit(formatted[i])) formattedDigitCount++;
    }
    final paddingDigits = formattedDigitCount - capped.length;
    final targetDigits = adjustedDigits + paddingDigits;

    // Walk the formatted string to find the character position after
    // [targetDigits] digit characters.
    int pos = formatted.length;
    int seen = 0;
    for (int i = 0; i < formatted.length; i++) {
      if (seen >= targetDigits) {
        pos = i;
        break;
      }
      if (_isDigit(formatted[i])) seen++;
      if (seen >= targetDigits) {
        pos = i + 1;
        break;
      }
    }

    return TextEditingValue(
      text: formatted,
      selection:
          TextSelection.collapsed(offset: pos.clamp(0, formatted.length)),
    );
  }

  static bool _isDigit(String c) =>
      c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;
}

/// Right-aligned time formatter that powers the digit-shift entry field.
///
/// Examples:
/// ```
/// formatDigitsAsTime('')      => ''
/// formatDigitsAsTime('5')     => '0:05'
/// formatDigitsAsTime('55')    => '0:55'
/// formatDigitsAsTime('551')   => '5:51'
/// formatDigitsAsTime('5512')  => '55:12'
/// formatDigitsAsTime('55120') => '5:51:20'
/// formatDigitsAsTime('551209')=> '55:12:09'
/// ```
@visibleForTesting
String formatDigitsAsTime(String digits) {
  if (digits.isEmpty) return '';
  final n = digits.length;
  if (n <= 2) {
    // SS → 0:SS (always show the leading "0:" so the user sees the unit).
    return '0:${digits.padLeft(2, '0')}';
  }
  if (n <= 4) {
    // M:SS or MM:SS — drop the leading zero on the minutes side.
    final ss = digits.substring(n - 2);
    final mm = digits.substring(0, n - 2);
    return '$mm:$ss';
  }
  // 5 or 6 digits → H:MM:SS or HH:MM:SS.
  final ss = digits.substring(n - 2);
  final mm = digits.substring(n - 4, n - 2);
  final hh = digits.substring(0, n - 4);
  return '$hh:$mm:$ss';
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
