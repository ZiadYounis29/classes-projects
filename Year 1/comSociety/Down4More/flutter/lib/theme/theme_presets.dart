import 'package:flutter/material.dart';

import 'theme_preset.dart';

/// The six built-in themes shipped with Down4More. Order matters; this is the
/// order they appear in the picker. Crimson is the default — it's the original
/// Down4More dark/red look from the Python prototype.
const List<ThemePreset> kBuiltInPresets = <ThemePreset>[
  ThemePreset(
    id: 'crimson',
    name: 'Crimson',
    primary: Color(0xFFFF3040),
    brightness: Brightness.dark,
    description: 'The original Down4More dark/red look.',
  ),
  ThemePreset(
    id: 'sky',
    name: 'Sky',
    primary: Color(0xFF1D4ED8),
    brightness: Brightness.light,
    description: 'Calm blue on white. Easy on the eyes in daylight.',
  ),
  ThemePreset(
    id: 'forest',
    name: 'Forest',
    primary: Color(0xFF10B981),
    brightness: Brightness.dark,
    description: 'Deep green on near-black. Classic terminal vibes.',
  ),
  ThemePreset(
    id: 'sunset',
    name: 'Sunset',
    primary: Color(0xFFFB923C),
    brightness: Brightness.dark,
    description: 'Warm orange on charcoal. Feels cozy.',
  ),
  ThemePreset(
    id: 'royal',
    name: 'Royal',
    primary: Color(0xFF8B5CF6),
    brightness: Brightness.dark,
    description: 'Vivid purple. Stands out without being loud.',
  ),
  ThemePreset(
    id: 'mono',
    name: 'Mono',
    primary: Color(0xFF111827),
    brightness: Brightness.light,
    description: 'Pure grayscale. The minimalist option.',
  ),
];

/// Identifier used for user-defined custom themes.
const String kCustomPresetId = 'custom';

ThemePreset? presetById(String id) {
  for (final p in kBuiltInPresets) {
    if (p.id == id) return p;
  }
  return null;
}
