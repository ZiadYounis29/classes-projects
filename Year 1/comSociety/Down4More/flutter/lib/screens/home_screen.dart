import 'package:flutter/material.dart';

import '../settings/app_settings.dart';
import '../theme/theme_controller.dart';
import '../widgets/d4m_logo.dart';
import 'batch_screen.dart';
import 'files_screen.dart';
import 'playlist_screen.dart';
import 'settings_screen.dart';
import 'single_screen.dart';

/// Top-level shell. Wide layouts (>= 720 px) get a [NavigationRail] on the
/// left; narrow layouts (phones) get a bottom [NavigationBar] with the logo in
/// an [AppBar].
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.themeController,
    required this.appSettings,
  });

  final ThemeController themeController;
  final AppSettings appSettings;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  static const List<_NavDestination> _destinations = [
    _NavDestination(Icons.link_outlined, Icons.link, 'Single'),
    _NavDestination(Icons.list_alt_outlined, Icons.list_alt, 'Playlist'),
    _NavDestination(Icons.dynamic_feed_outlined, Icons.dynamic_feed, 'Batch'),
    _NavDestination(Icons.folder_open_outlined, Icons.folder_open, 'My Files'),
    _NavDestination(Icons.settings_outlined, Icons.settings, 'Settings'),
  ];

  Widget _bodyAt(int i) {
    switch (i) {
      case 0:
        return SingleScreen(appSettings: widget.appSettings);
      case 1:
        return PlaylistScreen(appSettings: widget.appSettings);
      case 2:
        return BatchScreen(appSettings: widget.appSettings);
      case 3:
        return FilesScreen(appSettings: widget.appSettings);
      case 4:
        return SettingsScreen(
          themeController: widget.themeController,
          appSettings: widget.appSettings,
        );
      default:
        throw StateError('Unknown tab index $i');
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 720;
    final isExtraWide = width >= 1080;

    if (isWide) {
      return Scaffold(
        body: SafeArea(
          child: Row(
            children: [
              _SideNav(
                destinations: _destinations,
                selectedIndex: _selectedIndex,
                extended: isExtraWide,
                onSelected: (i) => setState(() => _selectedIndex = i),
              ),
              VerticalDivider(
                width: 1,
                color: Theme.of(context).colorScheme.outlineVariant,
              ),
              Expanded(child: _bodyAt(_selectedIndex)),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: const D4MLogo(showText: true, size: 22),
      ),
      body: SafeArea(child: _bodyAt(_selectedIndex)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        destinations: [
          for (final d in _destinations)
            NavigationDestination(
              icon: Icon(d.icon),
              selectedIcon: Icon(d.selectedIcon),
              label: d.label,
            ),
        ],
      ),
    );
  }
}

class _SideNav extends StatelessWidget {
  const _SideNav({
    required this.destinations,
    required this.selectedIndex,
    required this.onSelected,
    required this.extended,
  });

  final List<_NavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final bool extended;

  @override
  Widget build(BuildContext context) {
    return NavigationRail(
      extended: extended,
      selectedIndex: selectedIndex,
      onDestinationSelected: onSelected,
      labelType: extended
          ? NavigationRailLabelType.none
          : NavigationRailLabelType.all,
      leading: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: D4MLogo(showText: extended, size: extended ? 22 : 18),
      ),
      destinations: [
        for (final d in destinations)
          NavigationRailDestination(
            icon: Icon(d.icon),
            selectedIcon: Icon(d.selectedIcon),
            label: Text(d.label),
          ),
      ],
    );
  }
}

class _NavDestination {
  const _NavDestination(this.icon, this.selectedIcon, this.label);
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}
