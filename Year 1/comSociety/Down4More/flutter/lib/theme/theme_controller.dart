import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme_preset.dart';
import 'theme_presets.dart';

/// Holds the currently selected [ThemePreset] and persists changes via
/// shared_preferences. Listeners are notified after every change.
class ThemeController extends ChangeNotifier {
  ThemeController({SharedPreferences? prefs}) : _prefs = prefs;

  static const _kKeyPresetId = 'd4m.theme.id';
  static const _kKeyCustomPrimary = 'd4m.theme.custom.primary';
  static const _kKeyCustomBrightness = 'd4m.theme.custom.brightness';

  SharedPreferences? _prefs;
  ThemePreset _preset = kBuiltInPresets.first;

  ThemePreset get preset => _preset;

  /// Load the previously saved preset (if any) from disk. Should be called
  /// once at app startup before the first frame is shown.
  Future<void> load() async {
    _prefs ??= await SharedPreferences.getInstance();
    final id = _prefs!.getString(_kKeyPresetId);
    if (id == null) return;
    if (id == kCustomPresetId) {
      _preset = ThemePreset(
        id: kCustomPresetId,
        name: 'Custom',
        primary: Color(_prefs!.getInt(_kKeyCustomPrimary) ?? 0xFF888888),
        brightness: _prefs!.getString(_kKeyCustomBrightness) == 'light'
            ? Brightness.light
            : Brightness.dark,
        description: 'Your custom theme.',
      );
    } else {
      _preset = presetById(id) ?? kBuiltInPresets.first;
    }
    notifyListeners();
  }

  Future<void> setPreset(ThemePreset preset) async {
    _preset = preset;
    notifyListeners();
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(_kKeyPresetId, preset.id);
    if (preset.id == kCustomPresetId) {
      await _prefs!.setInt(_kKeyCustomPrimary, preset.primary.toARGB32());
      await _prefs!.setString(
        _kKeyCustomBrightness,
        preset.brightness == Brightness.light ? 'light' : 'dark',
      );
    }
  }
}

extension on Color {
  /// Hand-rolled equivalent of `value` (deprecated in newer Flutter) that gives
  /// a stable 0xAARRGGBB integer suitable for persistence.
  int toARGB32() {
    int channel(double v) => (v * 255.0).round().clamp(0, 255);
    return (channel(a) << 24) |
        (channel(r) << 16) |
        (channel(g) << 8) |
        channel(b);
  }
}
