import 'package:flutter/material.dart';

import '../models/output_format.dart';
import '../models/subtitle_settings.dart';
import '../models/video_metadata.dart';

/// Expandable card that lets the user opt into downloading subtitles for the
/// current video. Header shows a master switch + a one-line summary; the
/// expanded body shows the language picker (populated from the video's actual
/// available subtitle and auto-caption tracks), format picker, "embed in video"
/// toggle (gated to MP4 / MKV) and the auto-translate toggle.
///
/// When [metadata] is provided, the language dropdown is populated with:
///   • The video's real manual subtitle tracks (labelled "Subtitles")
///   • The video's real auto-caption tracks  (labelled "Auto-captions")
/// If [metadata] is null (e.g. batch/playlist use-case where one video hasn't
/// been pre-fetched), falls back to the static [kSubtitleLanguages] list with
/// an "Other…" custom text field, identical to the original behaviour.
///
/// Stateless from the controller's perspective: every change emits a fresh
/// [SubtitleSettings] via [onChanged] and the parent stores it. The widget
/// drives its expansion state internally so the parent only deals with the
/// data model.
///
/// Used by:
/// * SingleScreen (next to TrimInput in the "Slice & subtitles" row)
/// * BatchScreen + PlaylistScreen (global card in QualityMode.global)
/// * QueueItemRow (compact inline variant in QualityMode.perItem)
class SubtitleInput extends StatefulWidget {
  const SubtitleInput({
    super.key,
    required this.value,
    required this.onChanged,
    required this.outputFormat,
    this.metadata,
    this.enabled = true,
    this.compact = false,
  });

  /// Current settings. The widget is fully driven from this; toggling the
  /// master switch off doesn't reset the picker state, just the [enabled]
  /// field on the next emitted [SubtitleSettings].
  final SubtitleSettings value;

  /// Called whenever any sub-widget changes. The parent should store the
  /// new value and pass it back as [value] on the next build.
  final ValueChanged<SubtitleSettings> onChanged;

  /// Currently-selected output container/codec. Used to gate the
  /// "Embed in video" toggle — only MP4 / MKV are eligible.
  final OutputFormat outputFormat;

  /// Optional: the fetched video metadata. When provided, the language
  /// dropdown shows the video's real subtitle and auto-caption tracks.
  final VideoMetadata? metadata;

  /// Whether the whole control is interactive.
  final bool enabled;

  /// Compact mode: drop the surrounding card chrome and stretched padding.
  final bool compact;

  @override
  State<SubtitleInput> createState() => _SubtitleInputState();
}

class _SubtitleInputState extends State<SubtitleInput> {
  bool _expanded = false;
  late final TextEditingController _customLangController;

  @override
  void initState() {
    super.initState();
    _customLangController = TextEditingController(
      text: _isCustomLang(widget.value.language) ? widget.value.language : '',
    );
    _expanded = widget.value.enabled;
  }

  @override
  void didUpdateWidget(covariant SubtitleInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    final v = widget.value.language;
    if (_isCustomLang(v) && _customLangController.text != v) {
      _customLangController.text = v;
    }
  }

  @override
  void dispose() {
    _customLangController.dispose();
    super.dispose();
  }

  /// Returns true when [code] is a custom / typed language not in the static
  /// list AND not present in the video's actual tracks.
  bool _isCustomLang(String code) {
    if (code.isEmpty) return false;
    if (kSubtitleLanguages.any((l) => l.code == code)) return false;
    final m = widget.metadata;
    if (m != null) {
      if (m.availableSubtitleLangs.contains(code)) return false;
      if (m.availableAutoCaptionLangs.contains(code)) return false;
    }
    return true;
  }

  void _emit(SubtitleSettings next) {
    widget.onChanged(next.snapEmbedFor(widget.outputFormat));
  }

  void _toggleEnabled(bool on) {
    if (!widget.enabled) return;
    setState(() => _expanded = on);
    _emit(widget.value.copyWith(enabled: on));
  }

  void _setLanguage(String code, {required bool isAuto}) {
    _emit(widget.value.copyWith(language: code, useAutoCaption: isAuto));
  }

  void _setFormat(String ext) {
    _emit(widget.value.copyWith(format: ext));
  }

  void _setEmbed(bool on) {
    _emit(widget.value.copyWith(embed: on));
  }

  void _setAutoCaption(bool on) {
    final m = widget.metadata;
    final lang = widget.value.language;
    if (on && m != null) {
      // Switching to auto-captions. If the current language has an auto
      // track, keep it. Otherwise pick the first available auto language.
      if (m.availableAutoCaptionLangs.contains(lang)) {
        _emit(widget.value.copyWith(useAutoCaption: true));
      } else if (m.availableAutoCaptionLangs.isNotEmpty) {
        // Pick first common auto-caption language, or first overall.
        final firstCommon = m.availableAutoCaptionLangs.firstWhere(
          (c) => kSubtitleLanguages.any((l) => l.code == c),
          orElse: () => m.availableAutoCaptionLangs.first,
        );
        _emit(widget.value.copyWith(useAutoCaption: true, language: firstCommon));
      } else {
        _emit(widget.value.copyWith(useAutoCaption: true));
      }
    } else if (!on && m != null) {
      // Switching to manual subs. If the current language has a manual
      // track, keep it. Otherwise pick the first available manual language.
      if (m.availableSubtitleLangs.contains(lang)) {
        _emit(widget.value.copyWith(useAutoCaption: false));
      } else if (m.availableSubtitleLangs.isNotEmpty) {
        _emit(widget.value.copyWith(
            useAutoCaption: false, language: m.availableSubtitleLangs.first));
      } else {
        _emit(widget.value.copyWith(useAutoCaption: false));
      }
    } else {
      _emit(widget.value.copyWith(useAutoCaption: on));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final on = widget.value.enabled;

    final header = InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: widget.enabled
          ? () => setState(() => _expanded = !_expanded)
          : null,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: widget.compact ? 10 : 14,
          vertical: widget.compact ? 8 : 12,
        ),
        child: Row(
          children: [
            Icon(
              Icons.closed_caption_rounded,
              size: widget.compact ? 16 : 18,
              color: on ? scheme.primary : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Subtitles / transcript',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: on ? scheme.primary : scheme.onSurface,
                    ),
                  ),
                  if (!_expanded || widget.compact)
                    Text(
                      _summary(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Switch(
              value: on,
              onChanged: widget.enabled ? _toggleEnabled : null,
            ),
            Icon(
              _expanded ? Icons.expand_less : Icons.expand_more,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );

    final body = Padding(
      padding: EdgeInsets.fromLTRB(
        widget.compact ? 10 : 14,
        0,
        widget.compact ? 10 : 14,
        widget.compact ? 10 : 14,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1),
          const SizedBox(height: 10),
          _LanguageRow(
            value: widget.value.language,
            isAutoCaption: widget.value.useAutoCaption,
            customController: _customLangController,
            enabled: widget.enabled && on,
            metadata: widget.metadata,
            onChanged: _setLanguage,
          ),
          const SizedBox(height: 10),
          _FormatPicker(
            value: widget.value.format,
            enabled: widget.enabled && on,
            onChanged: _setFormat,
          ),
          const SizedBox(height: 8),
          _EmbedToggle(
            value: widget.value.embed,
            enabled:
                widget.enabled && on && outputFormatSupportsEmbed(widget.outputFormat),
            outputFormat: widget.outputFormat,
            onChanged: _setEmbed,
          ),
          const SizedBox(height: 4),
          _AutoCaptionToggle(
            value: widget.value.useAutoCaption,
            enabled: widget.enabled && on,
            onChanged: _setAutoCaption,
          ),
        ],
      ),
    );

    return Card(
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          header,
          if (_expanded) body,
        ],
      ),
    );
  }

  String _summary() {
    final v = widget.value;
    if (!v.enabled) return 'Off';
    final autoTag = v.useAutoCaption ? ' (auto)' : '';
    final parts = <String>['${v.language}$autoTag', v.format.toUpperCase()];
    if (v.embed && outputFormatSupportsEmbed(widget.outputFormat)) {
      parts.add('embed');
    } else {
      parts.add('separate file');
    }
    return parts.join(' · ');
  }
}

// ── Language row ─────────────────────────────────────────────────────────────

/// Unique value objects for each dropdown item so we can distinguish a manual
/// subtitle track from an auto-caption track even when they share the same
/// language code (e.g. both 'en' exist in subtitles AND automatic_captions).
class _LangOption {
  const _LangOption(this.code, this.label, {required this.isAuto});
  final String code;
  final String label;
  final bool isAuto;

  // Key used in the DropdownButtonFormField value — must be unique.
  String get dropdownKey => isAuto ? 'auto:$code' : 'sub:$code';
}

class _LanguageRow extends StatefulWidget {
  const _LanguageRow({
    required this.value,
    required this.isAutoCaption,
    required this.customController,
    required this.enabled,
    required this.onChanged,
    this.metadata,
  });

  final String value;
  final bool isAutoCaption;
  final TextEditingController customController;
  final bool enabled;
  final VideoMetadata? metadata;
  final void Function(String code, {required bool isAuto}) onChanged;

  @override
  State<_LanguageRow> createState() => _LanguageRowState();
}

class _LanguageRowState extends State<_LanguageRow> {
  static const String _otherKey = '__other__';

  /// Build the list of dropdown options.
  ///
  /// When metadata is available the list is filtered by the current toggle
  /// state: auto-captions ON → only auto-caption tracks, OFF → only manual
  /// subtitle tracks. This prevents the confusing mix of both types and
  /// ensures the toggle visibly controls what appears in the dropdown.
  /// If metadata is absent we fall back to the static language list.
  List<_LangOption> _buildOptions() {
    final m = widget.metadata;
    if (m != null &&
        (m.availableSubtitleLangs.isNotEmpty ||
            m.availableAutoCaptionLangs.isNotEmpty)) {
      if (widget.isAutoCaption) {
        // Auto-caption mode: show only auto-caption tracks.
        final opts = <_LangOption>[];
        for (final code in m.availableAutoCaptionLangs) {
          // Only show languages from the common list to keep the dropdown
          // manageable — YouTube typically has 100+ auto-translated langs.
          if (kSubtitleLanguages.any((l) => l.code == code)) {
            opts.add(
                _LangOption(code, '${_langLabel(code)} (auto)', isAuto: true));
          }
        }
        if (opts.isNotEmpty) return opts;
        // No common auto-caption tracks — fall through to static list.
      } else {
        // Manual mode: show only manual subtitle tracks.
        if (m.availableSubtitleLangs.isNotEmpty) {
          return [
            for (final code in m.availableSubtitleLangs)
              _LangOption(code, _langLabel(code), isAuto: false),
          ];
        }
        // No manual tracks — fall through to static list.
      }
    }
    // Fallback: static list, tagged to match the current toggle state.
    return [
      for (final l in kSubtitleLanguages)
        _LangOption(l.code, l.label, isAuto: widget.isAutoCaption),
    ];
  }

  /// Human-readable label for a language code. Looks up the static list first;
  /// falls back to just showing the code.
  String _langLabel(String code) {
    final match = kSubtitleLanguages.where((l) => l.code == code);
    return match.isNotEmpty ? match.first.label : code;
  }

  /// The current dropdown key derived from the current value + isAutoCaption.
  String _currentKey(List<_LangOption> options) {
    final targetKey = widget.isAutoCaption ? 'auto:${widget.value}' : 'sub:${widget.value}';
    if (options.any((o) => o.dropdownKey == targetKey)) return targetKey;
    // Also accept a match on just the code (fallback static list, isAuto=false).
    if (options.any((o) => o.code == widget.value && !o.isAuto)) {
      return 'sub:${widget.value}';
    }
    return _otherKey;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final options = _buildOptions();
    final currentKey = _currentKey(options);
    final hasRealTracks = widget.metadata != null &&
        (widget.metadata!.availableSubtitleLangs.isNotEmpty ||
            widget.metadata!.availableAutoCaptionLangs.isNotEmpty);

    // Build dropdown items. Since the options are already filtered by
    // toggle state (manual-only or auto-only), no section headers are
    // needed — all entries belong to the same type.
    final items = <DropdownMenuItem<String>>[];
    for (final opt in options) {
      items.add(DropdownMenuItem(
        value: opt.dropdownKey,
        child: Text(opt.label),
      ));
    }
    items.add(const DropdownMenuItem(
      value: _otherKey,
      child: Text('Other…'),
    ));

    // Ensure current value exists in items list.
    final validKeys = items
        .where((i) => i.value != null)
        .map((i) => i.value!)
        .toSet();

    // Pick the best fallback key based on toggle state.
    String bestFallback() {
      final prefix = widget.isAutoCaption ? 'auto:' : 'sub:';
      final first = validKeys.firstWhere(
          (k) => k.startsWith(prefix) && k != '__other__',
          orElse: () => '');
      if (first.isNotEmpty) return first;
      // If nothing matches the current mode, try any real track.
      final any = validKeys.firstWhere(
          (k) => k != '__other__',
          orElse: () => _otherKey);
      return any;
    }

    final effectiveKey = validKeys.contains(currentKey)
        ? currentKey
        : bestFallback();

    // If the stored value doesn't match any real track (e.g. default 'en' on a
    // video that only has auto-captions), silently correct the parent's state
    // after the frame so the dropdown shows a valid selection immediately.
    // When the video has no manual tracks at all but has English auto-captions,
    // this also handles the initial auto-selection so the user doesn't have to
    // manually switch to it.
    if (effectiveKey != currentKey && effectiveKey != _otherKey) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final isAuto = effectiveKey.startsWith('auto:');
        final code = isAuto ? effectiveKey.substring(5) : effectiveKey.substring(4);
        widget.onChanged(code, isAuto: isAuto);
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Info chip when real tracks were fetched.
        if (hasRealTracks)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Icon(Icons.check_circle_outline,
                    size: 13,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 4),
                Text(
                  _trackSummary(widget.metadata!),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
        DropdownButtonFormField<String>(
          isExpanded: true,
          value: effectiveKey,
          decoration: const InputDecoration(
            labelText: 'Language',
            prefixIcon: Icon(Icons.language_rounded),
            isDense: true,
            contentPadding:
                EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
          items: items,
          onChanged: widget.enabled
              ? (v) {
                  if (v == null || v == _otherKey) {
                    final raw = widget.customController.text.trim();
                    widget.onChanged(raw.isEmpty ? '' : raw, isAuto: false);
                  } else {
                    final isAuto = v.startsWith('auto:');
                    final code = isAuto ? v.substring(5) : v.substring(4);
                    widget.onChanged(code, isAuto: isAuto);
                  }
                }
              : null,
        ),
        if (currentKey == _otherKey) ...[
          const SizedBox(height: 8),
          TextField(
            controller: widget.customController,
            enabled: widget.enabled,
            onChanged: (v) => widget.onChanged(v.trim(), isAuto: false),
            decoration: const InputDecoration(
              labelText: 'IETF language tag',
              hintText: 'e.g. pt-BR, zh-Hant, en-orig',
              isDense: true,
              prefixIcon: Icon(Icons.translate_rounded),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "yt-dlp's --sub-langs accepts comma-separated tags too: "
            'e.g. en,fr.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
  }

  String _trackSummary(VideoMetadata m) {
    final parts = <String>[];
    if (m.availableSubtitleLangs.isNotEmpty) {
      parts.add('${m.availableSubtitleLangs.length} subtitle track'
          '${m.availableSubtitleLangs.length == 1 ? '' : 's'}');
    }
    if (m.availableAutoCaptionLangs.isNotEmpty) {
      parts.add('auto-captions available');
    }
    return parts.join(', ');
  }

}

// ── Format picker ─────────────────────────────────────────────────────────────

class _FormatPicker extends StatelessWidget {
  const _FormatPicker({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final String value;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      isExpanded: true,
      value: kSubtitleFormats.any((f) => f.ext == value)
          ? value
          : kDefaultSubtitleFormat.ext,
      decoration: const InputDecoration(
        labelText: 'Subtitle format',
        prefixIcon: Icon(Icons.subtitles_outlined),
        isDense: true,
        contentPadding:
            EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      items: [
        for (final f in kSubtitleFormats)
          DropdownMenuItem(value: f.ext, child: Text(f.label)),
      ],
      onChanged: enabled ? (v) => v == null ? null : onChanged(v) : null,
    );
  }
}

// ── Embed toggle ──────────────────────────────────────────────────────────────

class _EmbedToggle extends StatelessWidget {
  const _EmbedToggle({
    required this.value,
    required this.enabled,
    required this.outputFormat,
    required this.onChanged,
  });

  final bool value;
  final bool enabled;
  final OutputFormat outputFormat;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final supports = outputFormatSupportsEmbed(outputFormat);
    final disabledTooltip = supports
        ? null
        : "Embedding subtitles only works for MP4 and MKV. Pick one of those "
            "as the output format, or leave this off to save the subtitles "
            "as a separate file next to the video.";

    return Tooltip(
      message: disabledTooltip ?? '',
      preferBelow: true,
      child: SwitchListTile(
        value: value && supports,
        onChanged: enabled ? onChanged : null,
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(
          'Embed in video',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: enabled ? scheme.onSurface : scheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          supports
              ? 'Mux subtitles into the ${outputFormat.label} container so '
                  'players show them automatically.'
              : 'Not available for ${outputFormat.label} — subtitles will '
                  'save as a separate ${value ? "file " : ""}next to the video.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

// ── Auto-caption toggle ──────────────────────────────────────────────────────

class _AutoCaptionToggle extends StatelessWidget {
  const _AutoCaptionToggle({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SwitchListTile(
      value: value,
      onChanged: enabled ? onChanged : null,
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(
        'Use auto-captions',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: enabled ? scheme.onSurface : scheme.onSurfaceVariant,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        value
            ? 'Downloading auto-generated / auto-translated captions '
              '(available for most YouTube videos in any language).'
            : 'Download manually-uploaded subtitles only. Turn this on '
              'if the video has no manual subs in your language.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
