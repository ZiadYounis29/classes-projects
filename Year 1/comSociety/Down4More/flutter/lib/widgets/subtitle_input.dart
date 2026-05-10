import 'package:flutter/material.dart';

import '../models/output_format.dart';
import '../models/subtitle_settings.dart';

/// Expandable card that lets the user opt into downloading subtitles for the
/// current video. Header shows a master switch + a one-line summary; the
/// expanded body shows the language picker, format picker, "embed in video"
/// toggle (gated to MP4 / MKV) and the auto-translate toggle.
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
  /// "Embed in video" toggle — only MP4 / MKV are eligible. Audio formats
  /// disable embedding entirely.
  final OutputFormat outputFormat;

  /// Whether the whole control is interactive. Set to false during an
  /// active download so the user can't change subtitle settings mid-flight.
  final bool enabled;

  /// Compact mode: drop the surrounding card chrome and stretched padding,
  /// so the widget fits inside a queue item row without dominating.
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

  bool _isCustomLang(String code) =>
      code.isNotEmpty && !kSubtitleLanguages.any((l) => l.code == code);

  void _emit(SubtitleSettings next) {
    widget.onChanged(next.snapEmbedFor(widget.outputFormat));
  }

  void _toggleEnabled(bool on) {
    if (!widget.enabled) return;
    setState(() {
      _expanded = on;
    });
    _emit(widget.value.copyWith(enabled: on));
  }

  void _setLanguage(String code) {
    _emit(widget.value.copyWith(language: code));
  }

  void _setFormat(String ext) {
    _emit(widget.value.copyWith(format: ext));
  }

  void _setEmbed(bool on) {
    _emit(widget.value.copyWith(embed: on));
  }

  void _setAutoTranslate(bool on) {
    _emit(widget.value.copyWith(autoTranslate: on));
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
            customController: _customLangController,
            enabled: widget.enabled && on,
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
          _AutoTranslateToggle(
            value: widget.value.autoTranslate,
            enabled: widget.enabled && on,
            onChanged: _setAutoTranslate,
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
    final parts = <String>[v.language, v.format.toUpperCase()];
    if (v.embed && outputFormatSupportsEmbed(widget.outputFormat)) {
      parts.add('embed');
    } else {
      parts.add('separate file');
    }
    if (v.autoTranslate) parts.add('auto-translate');
    return parts.join(' · ');
  }
}

class _LanguageRow extends StatelessWidget {
  const _LanguageRow({
    required this.value,
    required this.customController,
    required this.enabled,
    required this.onChanged,
  });

  final String value;
  final TextEditingController customController;
  final bool enabled;
  final ValueChanged<String> onChanged;

  static const String _other = '__other__';

  bool get _isCustom =>
      value.isNotEmpty && !kSubtitleLanguages.any((l) => l.code == value);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = _isCustom ? _other : value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          isExpanded: true,
          value: kSubtitleLanguages.any((l) => l.code == selected) ||
                  selected == _other
              ? selected
              : kSubtitleLanguages.first.code,
          decoration: const InputDecoration(
            labelText: 'Language',
            prefixIcon: Icon(Icons.language_rounded),
            isDense: true,
            contentPadding:
                EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
          items: [
            for (final l in kSubtitleLanguages)
              DropdownMenuItem(
                value: l.code,
                child: Text(l.label),
              ),
            const DropdownMenuItem(
              value: _other,
              child: Text('Other…'),
            ),
          ],
          onChanged: enabled
              ? (v) {
                  if (v == null) return;
                  if (v == _other) {
                    final raw = customController.text.trim();
                    onChanged(raw.isEmpty ? '' : raw);
                  } else {
                    onChanged(v);
                  }
                }
              : null,
        ),
        if (selected == _other) ...[
          const SizedBox(height: 8),
          TextField(
            controller: customController,
            enabled: enabled,
            onChanged: (v) => onChanged(v.trim()),
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
}

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

class _AutoTranslateToggle extends StatelessWidget {
  const _AutoTranslateToggle({
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
        'Include auto-generated / auto-translated',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: enabled ? scheme.onSurface : scheme.onSurfaceVariant,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        'Falls back to YouTube auto-captions when the uploader did not ship '
        'manual subs in this language.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
