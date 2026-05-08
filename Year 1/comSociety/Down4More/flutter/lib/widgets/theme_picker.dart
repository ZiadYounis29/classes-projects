import 'package:flutter/material.dart';

import '../theme/theme_controller.dart';
import '../theme/theme_preset.dart';
import '../theme/theme_presets.dart';

/// The Settings → Appearance picker. Lists each built-in preset as a tappable
/// chip with a swatch, plus a "Custom theme" button that opens
/// [_CustomThemeDialog].
class ThemePicker extends StatelessWidget {
  const ThemePicker({super.key, required this.controller});

  final ThemeController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final selectedId = controller.preset.id;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Theme: ${controller.preset.name}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  controller.preset.description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color:
                            Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final p in kBuiltInPresets)
                      _PresetChip(
                        preset: p,
                        selected: p.id == selectedId,
                        onTap: () => controller.setPreset(p),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.colorize),
                      label: Text(
                        selectedId == kCustomPresetId
                            ? 'Edit custom theme'
                            : 'Custom theme',
                      ),
                      onPressed: () => _openCustomDialog(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openCustomDialog(BuildContext context) async {
    final result = await showDialog<ThemePreset>(
      context: context,
      builder: (_) => _CustomThemeDialog(initial: controller.preset),
    );
    if (result != null) {
      await controller.setPreset(result);
    }
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final ThemePreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? scheme.primaryContainer : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: preset.primary,
                shape: BoxShape.circle,
                border: Border.all(
                  color: scheme.onSurface.withValues(alpha: 0.15),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              preset.name,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: selected
                    ? scheme.onPrimaryContainer
                    : scheme.onSurface,
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 6),
              Icon(Icons.check_circle,
                  size: 16, color: scheme.onPrimaryContainer),
            ],
          ],
        ),
      ),
    );
  }
}

class _CustomThemeDialog extends StatefulWidget {
  const _CustomThemeDialog({required this.initial});

  final ThemePreset initial;

  @override
  State<_CustomThemeDialog> createState() => _CustomThemeDialogState();
}

class _CustomThemeDialogState extends State<_CustomThemeDialog> {
  late Color _primary = widget.initial.primary;
  late Brightness _brightness = widget.initial.brightness;

  static const _palette = <Color>[
    Color(0xFFFF3040), // crimson
    Color(0xFFFB923C), // orange
    Color(0xFFFACC15), // yellow
    Color(0xFF10B981), // emerald
    Color(0xFF06B6D4), // cyan
    Color(0xFF1D4ED8), // blue
    Color(0xFF8B5CF6), // violet
    Color(0xFFEC4899), // pink
    Color(0xFFF43F5E), // rose
    Color(0xFF14B8A6), // teal
    Color(0xFF6366F1), // indigo
    Color(0xFF111827), // ink
  ];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Custom theme'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Accent color',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final c in _palette)
                  _ColorSwatch(
                    color: c,
                    selected: c.toARGB32() == _primary.toARGB32(),
                    onTap: () => setState(() => _primary = c),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Text('Mode', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            SegmentedButton<Brightness>(
              segments: const [
                ButtonSegment(
                  value: Brightness.light,
                  label: Text('Light'),
                  icon: Icon(Icons.light_mode),
                ),
                ButtonSegment(
                  value: Brightness.dark,
                  label: Text('Dark'),
                  icon: Icon(Icons.dark_mode),
                ),
              ],
              selected: {_brightness},
              onSelectionChanged: (s) =>
                  setState(() => _brightness = s.first),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final preset = ThemePreset(
              id: kCustomPresetId,
              name: 'Custom',
              primary: _primary,
              brightness: _brightness,
              description: 'Your custom theme.',
            );
            Navigator.pop(context, preset);
          },
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.onSurface
                : Colors.transparent,
            width: 2.5,
          ),
        ),
        child: selected
            ? Icon(
                Icons.check,
                color:
                    color.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                size: 20,
              )
            : null,
      ),
    );
  }
}

extension on Color {
  int toARGB32() {
    int channel(double v) => (v * 255.0).round().clamp(0, 255);
    return (channel(a) << 24) |
        (channel(r) << 16) |
        (channel(g) << 8) |
        channel(b);
  }
}
