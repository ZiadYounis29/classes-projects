import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'theme/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final themeController = ThemeController();
  await themeController.load();
  runApp(Down4MoreApp(themeController: themeController));
}

class Down4MoreApp extends StatelessWidget {
  const Down4MoreApp({super.key, required this.themeController});

  final ThemeController themeController;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeController,
      builder: (context, _) {
        return MaterialApp(
          title: 'Down4More',
          debugShowCheckedModeBanner: false,
          theme: themeController.preset.toThemeData(),
          home: HomeScreen(themeController: themeController),
        );
      },
    );
  }
}
