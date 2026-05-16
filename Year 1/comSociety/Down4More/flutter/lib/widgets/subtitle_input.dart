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

  /// Returns true when we have confirmed metadata for this video (or merged
  /// metadata for a batch/playlist) but it carries absolutely no subtitle or
  /// auto-caption tracks. In that case the whole widget should be non-interactive.
  bool get _hasNoCaptions {
    final m = widget.metadata;
    if (m == null) return false; // no metadata yet → allow static fallback
    return m.availableSubtitleLangs.isEmpty &&
        m.availableAutoCaptionLangs.isEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final on = widget.value.enabled;
    // When the video has no captions at all, treat the whole control as
    // disabled regardless of what the parent says.
    final effectivelyEnabled = widget.enabled && !_hasNoCaptions;

    final header = InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: effectivelyEnabled
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
              _hasNoCaptions
                  ? Icons.closed_caption_disabled_outlined
                  : Icons.closed_caption_rounded,
              size: widget.compact ? 16 : 18,
              color: _hasNoCaptions
                  ? scheme.onSurfaceVariant.withOpacity(0.5)
                  : on
                      ? scheme.primary
                      : scheme.onSurfaceVariant,
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
                      color: _hasNoCaptions
                          ? scheme.onSurfaceVariant.withOpacity(0.5)
                          : on
                              ? scheme.primary
                              : scheme.onSurface,
                    ),
                  ),
                  Text(
                    _hasNoCaptions
                        ? 'No captions available for this video'
                        : (!_expanded || widget.compact)
                            ? _summary()
                            : '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _hasNoCaptions
                          ? scheme.onSurfaceVariant.withOpacity(0.5)
                          : scheme.onSurfaceVariant,
                      fontStyle: _hasNoCaptions
                          ? FontStyle.italic
                          : FontStyle.normal,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Switch(
              value: on && !_hasNoCaptions,
              onChanged: effectivelyEnabled ? _toggleEnabled : null,
            ),
            // Hide the expand chevron when there's nothing to expand.
            if (!_hasNoCaptions)
              Icon(
                _expanded ? Icons.expand_less : Icons.expand_more,
                color: scheme.onSurfaceVariant,
              )
            else
              Icon(
                Icons.block_outlined,
                size: 18,
                color: scheme.onSurfaceVariant.withOpacity(0.4),
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
            enabled: effectivelyEnabled && on,
            metadata: widget.metadata,
            onChanged: _setLanguage,
          ),
          const SizedBox(height: 10),
          _FormatPicker(
            value: widget.value.format,
            enabled: effectivelyEnabled && on,
            onChanged: _setFormat,
          ),
          const SizedBox(height: 8),
          _EmbedToggle(
            value: widget.value.embed,
            enabled:
                effectivelyEnabled && on && outputFormatSupportsEmbed(widget.outputFormat),
            outputFormat: widget.outputFormat,
            onChanged: _setEmbed,
          ),
        ],
      ),
    );

    return Card(
      margin: EdgeInsets.zero,
      color: _hasNoCaptions ? scheme.surfaceContainerLow.withOpacity(0.6) : scheme.surfaceContainerLow,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: _hasNoCaptions ? scheme.outlineVariant.withOpacity(0.5) : scheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          header,
          if (_expanded && !_hasNoCaptions) body,
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
  /// When metadata is available we show the video's real manually-uploaded
  /// subtitle tracks, plus an English auto-caption entry if one exists and
  /// no manual English track is already present.
  /// If metadata is absent we fall back to the static language list.
  List<_LangOption> _buildOptions() {
    final m = widget.metadata;
    if (m != null &&
        (m.availableSubtitleLangs.isNotEmpty ||
            m.availableAutoCaptionLangs.isNotEmpty)) {
      final opts = <_LangOption>[
        for (final code in m.availableSubtitleLangs)
          _LangOption(code, _langLabel(code), isAuto: false),
      ];
      // Add auto-caption tracks for any language not already covered by a
      // manual subtitle track. This correctly handles 'en-orig' (YouTube's
      // raw speech-recognition track) which would be missed if we only looked
      // for plain 'en'.
      for (final code in m.availableAutoCaptionLangs) {
        if (opts.any((o) => !o.isAuto && o.code == code)) continue;
        opts.add(_LangOption(code, _autoLangLabel(code), isAuto: true));
      }
      return opts;
    }
    // Fallback: static list (all treated as manual).
    return [
      for (final l in kSubtitleLanguages)
        _LangOption(l.code, l.label, isAuto: false),
    ];
  }

  /// Human-readable label for a language code. Looks up the static list first;
  /// falls back to just showing the code.
  String _langLabel(String code) {
    final match = kSubtitleLanguages.where((l) => l.code == code);
    return match.isNotEmpty ? match.first.label : code;
  }

  /// Human-readable label for an auto-caption (-orig) track.
  /// e.g. 'en-orig' → 'English (auto)', 'ar-orig' → 'Arabic (auto)',
  /// 'auto-orig' (sentinel) → 'Original language (auto)'.
  String _autoLangLabel(String code) {
    // Sentinel used in batch/playlist mode: no specific language known yet.
    if (code == kAutoOrigSentinel) return 'Original language (auto)';
    // code is always '<lang>-orig' — strip the suffix to get the base language.
    final baseLang = code.endsWith('-orig')
        ? code.substring(0, code.length - 5)
        : code;
    final match = kSubtitleLanguages.where((l) => l.code == baseLang);
    final langName = match.isNotEmpty
        ? match.first.label.split(' (').first // e.g. "English" from "English (en)"
        : baseLang;
    return '$langName (auto)';
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

    // Build dropdown items. When real tracks are available, manual subtitle
    // tracks appear first (under a section header if there are any), followed
    // by the single English auto-caption entry (if present and no manual
    // English track exists). The static fallback list has no section headers.
    final items = <DropdownMenuItem<String>>[];
    if (hasRealTracks) {
      if (options.any((o) => !o.isAuto)) {
        items.add(_sectionHeader(context, 'Subtitles'));
        for (final opt in options.where((o) => !o.isAuto)) {
          items.add(DropdownMenuItem(
            value: opt.dropdownKey,
            child: Text(opt.label),
          ));
        }
      }
      final autoOpts = options.where((o) => o.isAuto).toList();
      if (autoOpts.isNotEmpty) {
        items.add(_sectionHeader(context, 'Auto-captions'));
        for (final opt in autoOpts) {
          items.add(DropdownMenuItem(
            value: opt.dropdownKey,
            child: Text(opt.label),
          ));
        }
      }
      items.add(const DropdownMenuItem(
        value: _otherKey,
        child: Text('Other…'),
      ));
    } else {
      // Static list fallback.
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
    }

    // Ensure current value exists in items list.
    final validKeys = items
        .where((i) => i.value != null && i.child is! _SectionHeaderChild)
        .map((i) => i.value!)
        .toSet();

    // Pick the best fallback key: prefer the current value, then first manual
    // sub, then first auto-caption, then Other.
    String bestFallback() {
      // Try first manual sub track.
      final firstManual = validKeys.firstWhere(
          (k) => k.startsWith('sub:') && k != '__other__',
          orElse: () => '');
      if (firstManual.isNotEmpty) return firstManual;
      // Try first auto-caption track.
      final firstAuto = validKeys.firstWhere(
          (k) => k.startsWith('auto:'),
          orElse: () => '');
      if (firstAuto.isNotEmpty) return firstAuto;
      return _otherKey;
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
      // Count only auto-caption languages not already covered by manual tracks.
      final extraAuto = m.availableAutoCaptionLangs
          .where((c) => !m.availableSubtitleLangs.contains(c))
          .length;
      if (extraAuto > 0) {
        parts.add('$extraAuto auto-caption track'
            '${extraAuto == 1 ? '' : 's'}');
      }
    }
    return parts.join(', ');
  }

  /// Non-interactive section header item rendered as a disabled label.
  static DropdownMenuItem<String> _sectionHeader(
      BuildContext context, String label) {
    final theme = Theme.of(context);
    return DropdownMenuItem<String>(
      enabled: false,
      // Use a unique value that won't clash with any real key.
      value: '__section__$label',
      child: _SectionHeaderChild(label: label, theme: theme),
    );
  }
}

/// The widget used as a section-header child inside the dropdown. Also used as
/// a type-tag so [_LanguageRow] can filter it out of the "valid keys" set.
class _SectionHeaderChild extends StatelessWidget {
  const _SectionHeaderChild({required this.label, required this.theme});
  final String label;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.primary,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
      ),
    );
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
