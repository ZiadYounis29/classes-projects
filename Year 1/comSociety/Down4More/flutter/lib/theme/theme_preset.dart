import 'package:flutter/material.dart';

/// A named look-and-feel for the Down4More app.
///
/// A preset has a primary (accent) color, a seed color used to derive the rest
/// of the Material 3 [ColorScheme], and a [Brightness]. The built-in presets
/// live in `theme_presets.dart`; user-edited custom themes are persisted by
/// [ThemeController] using the same shape.
@immutable
class ThemePreset {
  const ThemePreset({
    required this.id,
    required this.name,
    required this.primary,
    required this.seed,
    required this.brightness,
    required this.description,
  });

  /// Stable identifier used as the persistence key. Lowercase, no spaces.
  final String id;

  /// Human-readable name shown in the picker.
  final String name;

  /// The accent color. Used for the "4More" half of the logo, primary buttons,
  /// progress indicators, the active nav rail destination, etc.
  final Color primary;

  /// Seed for the rest of the [ColorScheme]. For dark themes this is usually
  /// a near-black; for light themes a near-white.
  final Color seed;

  final Brightness brightness;

  /// One-sentence blurb shown under the preset name in the picker.
  final String description;

  /// Build a Material 3 [ThemeData] from this preset.
  ThemeData toThemeData() {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: brightness,
      primary: primary,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      visualDensity: VisualDensity.standard,
      cardTheme: CardTheme(
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        color: scheme.surfaceContainerLow,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: scheme.surface,
        selectedIconTheme: IconThemeData(color: scheme.primary),
        selectedLabelTextStyle: TextStyle(
          color: scheme.primary,
          fontWeight: FontWeight.w600,
        ),
        unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
        indicatorColor: scheme.primaryContainer,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
      ),
    );
  }
}
