import 'package:down4more/main.dart';
import 'package:down4more/services/download_history.dart';
import 'package:down4more/settings/app_settings.dart';
import 'package:down4more/theme/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('App boots with the 5-tab shell visible', (tester) async {
    final controller = ThemeController();
    await controller.load();

    // Force a wide layout so the NavigationRail is rendered (which shows all
    // five destination labels regardless of width).
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final appSettings = AppSettings();
    await appSettings.load();
    final history = DownloadHistory();
    await history.load();

    await tester.pumpWidget(Down4MoreApp(
      themeController: controller,
      appSettings: appSettings,
      history: history,
    ));
    // Use pump() instead of pumpAndSettle() because IndexedStack keeps all
    // tab screens alive and some contain ongoing animations.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Single'), findsOneWidget);
    expect(find.text('Playlist'), findsOneWidget);
    expect(find.text('Batch'), findsOneWidget);
    expect(find.text('My Files'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('Tapping Settings reveals Appearance section', (tester) async {
    final controller = ThemeController();
    await controller.load();

    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final appSettings = AppSettings();
    await appSettings.load();
    final history = DownloadHistory();
    await history.load();

    await tester.pumpWidget(Down4MoreApp(
      themeController: controller,
      appSettings: appSettings,
      history: history,
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.text('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('APPEARANCE'), findsOneWidget);
    expect(find.text('Theme: Crimson'), findsOneWidget);
  });
}
