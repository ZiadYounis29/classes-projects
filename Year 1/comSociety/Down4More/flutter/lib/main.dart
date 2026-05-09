import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'settings/app_settings.dart';
import 'theme/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final themeController = ThemeController();
  final appSettings     = AppSettings();
  await Future.wait([themeController.load(), appSettings.load()]);
  runApp(Down4MoreApp(themeController: themeController, appSettings: appSettings));
}

class Down4MoreApp extends StatelessWidget {
  const Down4MoreApp({
    super.key,
    required this.themeController,
    required this.appSettings,
  });

  final ThemeController themeController;
  final AppSettings appSettings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeController,
      builder: (context, _) {
        return MaterialApp(
          title: 'Down4More',
          debugShowCheckedModeBanner: false,
          theme: themeController.preset.toThemeData(),
          home: HomeScreen(
            themeController: themeController,
            appSettings: appSettings,
          ),
        );
      },
    );
  }
}
