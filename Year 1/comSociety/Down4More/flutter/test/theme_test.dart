import 'package:down4more/theme/theme_controller.dart';
import 'package:down4more/theme/theme_preset.dart';
import 'package:down4more/theme/theme_presets.dart';
import 'package:down4more/widgets/theme_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Theme presets', () {
    test('built-in preset ids are unique', () {
      final ids = kBuiltInPresets.map((p) => p.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('built-in preset names are non-empty', () {
      for (final p in kBuiltInPresets) {
        expect(p.name, isNotEmpty);
      }
    });

    test('every preset produces a valid Material 3 ThemeData', () {
      for (final p in kBuiltInPresets) {
        final t = p.toThemeData();
        expect(t.useMaterial3, isTrue);
        expect(t.colorScheme.brightness, equals(p.brightness));
        expect(t.colorScheme.primary, isNotNull);
      }
    });

    test('"crimson" is the default first preset', () {
      expect(kBuiltInPresets.first.id, equals('crimson'));
    });

    test('presetById returns null for unknown ids', () {
      expect(presetById('does-not-exist'), isNull);
    });

    test('presetById finds each built-in by id', () {
      for (final p in kBuiltInPresets) {
        expect(presetById(p.id), equals(p));
      }
    });
  });

  group('ThemeController', () {
    test('starts on the first built-in preset before load()', () {
      final c = ThemeController();
      expect(c.preset.id, equals(kBuiltInPresets.first.id));
    });

    test('persists and re-loads the selected preset', () async {
      final c1 = ThemeController();
      await c1.load();
      await c1.setPreset(kBuiltInPresets.firstWhere((p) => p.id == 'forest'));

      final c2 = ThemeController();
      await c2.load();
      expect(c2.preset.id, equals('forest'));
    });

    test('persists a custom theme with the chosen primary + brightness',
        () async {
      final c1 = ThemeController();
      await c1.load();
      await c1.setPreset(
        const ThemePreset(
          id: kCustomPresetId,
          name: 'Custom',
          primary: Color(0xFF00BFA5),
          seed: Color(0xFF0F0F12),
          brightness: Brightness.dark,
          description: 'Your custom theme.',
        ),
      );

      final c2 = ThemeController();
      await c2.load();
      expect(c2.preset.id, equals(kCustomPresetId));
      expect(c2.preset.brightness, equals(Brightness.dark));
      expect(_argb(c2.preset.primary), equals(0xFF00BFA5));
    });

    test('falls back to default preset when persisted id is unknown',
        () async {
      SharedPreferences.setMockInitialValues({
        'd4m.theme.id': 'made-up-name',
      });
      final c = ThemeController();
      await c.load();
      expect(c.preset.id, equals(kBuiltInPresets.first.id));
    });

    test('notifyListeners fires on setPreset', () async {
      final c = ThemeController();
      await c.load();
      var calls = 0;
      c.addListener(() => calls++);
      await c.setPreset(kBuiltInPresets[1]);
      expect(calls, greaterThan(0));
    });
  });

  group('ThemePicker widget', () {
    testWidgets('renders a chip per built-in preset and reflects selection',
        (tester) async {
      final controller = ThemeController();
      await controller.load();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: controller,
              builder: (_, __) => ThemePicker(controller: controller),
            ),
          ),
        ),
      );

      for (final p in kBuiltInPresets) {
        expect(find.text(p.name), findsOneWidget);
      }

      await tester.tap(find.text('Forest'));
      await tester.pump();
      expect(controller.preset.id, equals('forest'));
      expect(find.text('Theme: Forest'), findsOneWidget);
    });
  });
}

int _argb(Color c) {
  int channel(double v) => (v * 255.0).round().clamp(0, 255);
  return (channel(c.a) << 24) |
      (channel(c.r) << 16) |
      (channel(c.g) << 8) |
      channel(c.b);
}
