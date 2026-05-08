import 'package:flutter/material.dart';

import '../theme/theme_controller.dart';
import '../widgets/theme_picker.dart';

/// PR 2 ships only the Appearance section live. Everything else (download
/// folder, format, network, retry) renders as disabled placeholders so the
/// shell looks complete while real persistence lands in PR 5.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.themeController});

  final ThemeController themeController;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      children: [
        Text(
          'Settings',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'Configure how Down4More looks and behaves.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 24),
        _SectionHeader(icon: Icons.palette_outlined, title: 'Appearance'),
        const SizedBox(height: 12),
        ThemePicker(controller: themeController),
        const SizedBox(height: 32),
        _SectionHeader(icon: Icons.folder_outlined, title: 'Downloads'),
        const SizedBox(height: 12),
        const _DisabledTile(
          icon: Icons.folder_special_outlined,
          title: 'Download folder',
          subtitle: 'Where your downloads land',
          chip: 'Coming in PR 5',
        ),
        const SizedBox(height: 8),
        const _DisabledTile(
          icon: Icons.cleaning_services_outlined,
          title: 'Keep partial files on cancel',
          subtitle: 'Don\'t delete in-progress downloads when cancelling',
          chip: 'Coming in PR 5',
        ),
        const SizedBox(height: 32),
        _SectionHeader(icon: Icons.tune, title: 'Defaults'),
        const SizedBox(height: 12),
        const _DisabledTile(
          icon: Icons.movie_filter_outlined,
          title: 'Default format',
          subtitle: 'MP4, WebM, MKV…',
          chip: 'Coming in PR 5',
        ),
        const SizedBox(height: 8),
        const _DisabledTile(
          icon: Icons.high_quality_outlined,
          title: 'Default quality',
          subtitle: 'Best available, 1080p, 720p…',
          chip: 'Coming in PR 5',
        ),
        const SizedBox(height: 8),
        const _DisabledTile(
          icon: Icons.bolt_outlined,
          title: 'Default concurrency',
          subtitle: 'How many downloads run at once',
          chip: 'Coming in PR 5',
        ),
        const SizedBox(height: 32),
        _SectionHeader(icon: Icons.cloud_outlined, title: 'Network'),
        const SizedBox(height: 12),
        const _DisabledTile(
          icon: Icons.speed_outlined,
          title: 'Speed limit',
          subtitle: 'Cap download rate (yt-dlp --rate-limit)',
          chip: 'Coming in PR 5',
        ),
        const SizedBox(height: 32),
        _SectionHeader(icon: Icons.replay_circle_filled_outlined, title: 'Auto-retry'),
        const SizedBox(height: 12),
        const _DisabledTile(
          icon: Icons.refresh_outlined,
          title: 'Max retries on failure',
          subtitle: 'How many times to retry a failed download',
          chip: 'Coming in PR 6',
        ),
        const SizedBox(height: 8),
        const _DisabledTile(
          icon: Icons.timer_outlined,
          title: 'Delay between retries',
          subtitle: 'Wait this long before each retry',
          chip: 'Coming in PR 6',
        ),
        const SizedBox(height: 32),
        Center(
          child: Text(
            'Down4More — PR 2 of 10 (scaffold). More features land each PR.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 20, color: scheme.primary),
        const SizedBox(width: 8),
        Text(
          title.toUpperCase(),
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                letterSpacing: 1.6,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
        ),
      ],
    );
  }
}

class _DisabledTile extends StatelessWidget {
  const _DisabledTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.chip,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String chip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Opacity(
          opacity: 0.55,
          child: Row(
            children: [
              Icon(icon, color: scheme.onSurfaceVariant),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Chip(
                visualDensity: VisualDensity.compact,
                label: Text(
                  chip,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                ),
                backgroundColor: scheme.secondaryContainer,
                side: BorderSide.none,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
