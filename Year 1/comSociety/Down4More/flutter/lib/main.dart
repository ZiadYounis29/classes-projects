import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/download_history.dart';
import 'services/notification_service.dart';
import 'settings/app_settings.dart';
import 'theme/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final themeController = ThemeController();
  final appSettings     = AppSettings();
  final history         = DownloadHistory();

  await Future.wait([
    themeController.load(),
    appSettings.load(),
    history.load(),
    NotificationService.init(),
  ]);

  // Sync the static flag and keep it in sync as the setting changes.
  NotificationService.enabled = appSettings.notificationsEnabled;
  appSettings.addListener(() {
    NotificationService.enabled = appSettings.notificationsEnabled;
  });

  runApp(Down4MoreApp(
    themeController: themeController,
    appSettings: appSettings,
    history: history,
  ));
}

class Down4MoreApp extends StatelessWidget {
  const Down4MoreApp({
    super.key,
    required this.themeController,
    required this.appSettings,
    required this.history,
  });

  final ThemeController themeController;
  final AppSettings appSettings;
  final DownloadHistory history;

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
            history: history,
          ),
        );
      },
    );
  }
}
