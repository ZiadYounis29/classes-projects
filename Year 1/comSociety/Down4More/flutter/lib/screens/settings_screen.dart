import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/output_format.dart';
import '../settings/app_settings.dart';
import '../theme/theme_controller.dart';
import '../widgets/theme_picker.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.themeController,
    required this.appSettings,
  });

  final ThemeController themeController;
  final AppSettings appSettings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: appSettings,
      builder: (context, _) {
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

            // ── Appearance ──────────────────────────────────────────────────
            const _SectionHeader(icon: Icons.palette_outlined, title: 'Appearance'),
            const SizedBox(height: 12),
            ThemePicker(controller: themeController),
            const SizedBox(height: 32),

            // ── Downloads ───────────────────────────────────────────────────
            const _SectionHeader(icon: Icons.folder_outlined, title: 'Downloads'),
            const SizedBox(height: 12),
            _FolderPickerTile(appSettings: appSettings),
            const SizedBox(height: 8),
            _SwitchTile(
              icon: Icons.cleaning_services_outlined,
              title: 'Keep partial files on cancel',
              subtitle: "Don't delete in-progress files when cancelling",
              value: appSettings.keepPartial,
              onChanged: appSettings.setKeepPartial,
            ),
            const SizedBox(height: 32),

            // ── Defaults ────────────────────────────────────────────────────
            const _SectionHeader(icon: Icons.tune, title: 'Defaults'),
            const SizedBox(height: 12),
            _FormatTile(appSettings: appSettings),
            const SizedBox(height: 8),
            _DropdownTile<String>(
              icon: Icons.high_quality_outlined,
              title: 'Default quality',
              subtitle: 'Applied when opening the Single screen',
              value: appSettings.defaultQuality,
              items: const [
                DropdownMenuItem(value: 'best',   child: Text('Best available')),
                DropdownMenuItem(value: '2160p',  child: Text('4K (2160p)')),
                DropdownMenuItem(value: '1440p',  child: Text('1440p')),
                DropdownMenuItem(value: '1080p',  child: Text('1080p')),
                DropdownMenuItem(value: '720p',   child: Text('720p')),
                DropdownMenuItem(value: '480p',   child: Text('480p')),
                DropdownMenuItem(value: '360p',   child: Text('360p')),
                DropdownMenuItem(value: 'audio',  child: Text('Audio only')),
              ],
              onChanged: appSettings.setDefaultQuality,
            ),
            const SizedBox(height: 8),
            _StepperTile(
              icon: Icons.layers_outlined,
              title: 'Max concurrent downloads',
              subtitle: 'Used by the Batch screen (1–8)',
              value: appSettings.concurrency,
              min: 1,
              max: 8,
              onChanged: appSettings.setConcurrency,
            ),
            const SizedBox(height: 32),

            // ── Network ─────────────────────────────────────────────────────
            const _SectionHeader(icon: Icons.cloud_outlined, title: 'Network'),
            const SizedBox(height: 12),
            _SpeedLimitTile(appSettings: appSettings),
            const SizedBox(height: 32),

            // ── Auto-retry ──────────────────────────────────────────────────
            const _SectionHeader(
                icon: Icons.replay_circle_filled_outlined, title: 'Auto-retry'),
            const SizedBox(height: 12),
            _StepperTile(
              icon: Icons.refresh_outlined,
              title: 'Max retries on failure',
              subtitle: '0 = disabled',
              value: appSettings.autoRetry,
              min: 0,
              max: 10,
              onChanged: appSettings.setAutoRetry,
            ),
            const SizedBox(height: 8),
            _StepperTile(
              icon: Icons.timer_outlined,
              title: 'Delay between retries',
              subtitle: 'Seconds to wait before each retry (1–60)',
              value: appSettings.retryDelay,
              min: 1,
              max: 60,
              step: 5,
              onChanged: appSettings.setRetryDelay,
            ),
            const SizedBox(height: 32),
            Center(
              child: Text(
                'Down4More — all settings persist automatically.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }
}

// ── Section header ────────────────────────────────────────────────────────────

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

// ── Base card shell ───────────────────────────────────────────────────────────

class _SettingCard extends StatelessWidget {
  const _SettingCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: child,
      ),
    );
  }
}

// ── Folder picker tile ────────────────────────────────────────────────────────

class _FolderPickerTile extends StatelessWidget {
  const _FolderPickerTile({required this.appSettings});
  final AppSettings appSettings;

  Future<void> _pick(BuildContext context) async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => _FolderInputDialog(initial: appSettings.downloadDir),
    );
    if (result != null) {
      await appSettings.setDownloadDir(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme  = Theme.of(context).colorScheme;
    final theme   = Theme.of(context);
    final current = appSettings.downloadDir;

    return _SettingCard(
      child: Row(
        children: [
          Icon(Icons.folder_special_outlined, color: scheme.onSurfaceVariant),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Download folder',
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w600)),
                Text(
                  current.isEmpty ? 'Default — ~/Downloads/Down4More' : current,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontFamily: current.isEmpty ? null : 'monospace',
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              FilledButton.tonalIcon(
                onPressed: () => _pick(context),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Change'),
              ),
              if (current.isNotEmpty) ...[
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () => appSettings.setDownloadDir(''),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  child: const Text('Reset to default'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _FolderInputDialog extends StatefulWidget {
  const _FolderInputDialog({required this.initial});
  final String initial;

  @override
  State<_FolderInputDialog> createState() => _FolderInputDialogState();
}

class _FolderInputDialogState extends State<_FolderInputDialog> {
  late final TextEditingController _ctrl;
  String? _error;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final val = _ctrl.text.trim();
    if (val.isEmpty) { Navigator.of(context).pop(''); return; }
    if (!val.startsWith('/') && !(val.length > 1 && val[1] == ':')) {
      setState(() => _error = 'Enter an absolute path');
      return;
    }
    Navigator.of(context).pop(val);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Download folder'),
      content: SizedBox(
        width: 400,
        child: TextField(
          controller: _ctrl,
          autofocus: true,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: 'Absolute path',
            hintText: '/home/user/Videos',
            errorText: _error,
            prefixIcon: const Icon(Icons.folder_outlined),
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Save')),
      ],
    );
  }
}

// ── Switch tile ───────────────────────────────────────────────────────────────

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final Future<void> Function(bool) onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme  = Theme.of(context);
    return _SettingCard(
      child: Row(
        children: [
          Icon(icon, color: scheme.onSurfaceVariant),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w600)),
                Text(subtitle,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

// ── Format tile (dual video + audio dropdowns) ────────────────────────────────

class _FormatTile extends StatelessWidget {
  const _FormatTile({required this.appSettings});
  final AppSettings appSettings;

  static const _videoItems = <DropdownMenuItem<String>>[
    DropdownMenuItem(value: 'mp4',  child: Text('MP4 — Best compatibility')),
    DropdownMenuItem(value: 'mkv',  child: Text('MKV — Keeps all streams')),
    DropdownMenuItem(value: 'webm', child: Text('WebM — Open format')),
  ];

  static const _audioItems = <DropdownMenuItem<String>>[
    DropdownMenuItem(value: 'm4a',  child: Text('M4A — AAC in MPEG-4')),
    DropdownMenuItem(value: 'mp3',  child: Text('MP3 — Universal')),
    DropdownMenuItem(value: 'opus', child: Text('Opus — Best quality/bit')),
    DropdownMenuItem(value: 'flac', child: Text('FLAC — Lossless')),
    DropdownMenuItem(value: 'wav',  child: Text('WAV — Uncompressed')),
    DropdownMenuItem(value: 'ogg',  child: Text('OGG — Vorbis')),
  ];

  static const _videoExts = {'mp4', 'mkv', 'webm'};
  static const _audioExts = {'m4a', 'mp3', 'opus', 'flac', 'wav', 'ogg'};

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme  = Theme.of(context);
    final fmt    = appSettings.defaultFormat;
    final videoVal = _videoExts.contains(fmt) ? fmt : 'mp4';
    final audioVal = _audioExts.contains(fmt) ? fmt : 'm4a';

    return _SettingCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.movie_filter_outlined, color: scheme.onSurfaceVariant),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Default format',
                        style: theme.textTheme.bodyLarge
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    Text('Container applied to new downloads',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: videoVal,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Video',
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  items: _videoItems,
                  onChanged: (v) { if (v != null) appSettings.setDefaultFormat(v); },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: audioVal,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Audio',
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  items: _audioItems,
                  onChanged: (v) { if (v != null) appSettings.setDefaultFormat(v); },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Generic dropdown tile ─────────────────────────────────────────────────────

class _DropdownTile<T> extends StatelessWidget {
  const _DropdownTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final T value;
  final List<DropdownMenuItem<T>> items;
  final Future<void> Function(T) onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme  = Theme.of(context);
    return _SettingCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: scheme.onSurfaceVariant),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: theme.textTheme.bodyLarge
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    Text(subtitle,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<T>(
            value: value,
            isExpanded: true,
            decoration: const InputDecoration(
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            items: items,
            onChanged: (v) { if (v != null) onChanged(v); },
          ),
        ],
      ),
    );
  }
}

// ── Stepper tile (+/- integer control) ───────────────────────────────────────

class _StepperTile extends StatelessWidget {
  const _StepperTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.step = 1,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final int value;
  final int min;
  final int max;
  final int step;
  final Future<void> Function(int) onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme  = Theme.of(context);
    return _SettingCard(
      child: Row(
        children: [
          Icon(icon, color: scheme.onSurfaceVariant),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w600)),
                Text(subtitle,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton.filledTonal(
                onPressed: value > min ? () => onChanged(value - step) : null,
                icon: const Icon(Icons.remove),
                visualDensity: VisualDensity.compact,
              ),
              SizedBox(
                width: 40,
                child: Text(
                  '$value',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton.filledTonal(
                onPressed: value < max ? () => onChanged(value + step) : null,
                icon: const Icon(Icons.add),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Speed limit tile ──────────────────────────────────────────────────────────

class _SpeedLimitTile extends StatefulWidget {
  const _SpeedLimitTile({required this.appSettings});
  final AppSettings appSettings;

  @override
  State<_SpeedLimitTile> createState() => _SpeedLimitTileState();
}

class _SpeedLimitTileState extends State<_SpeedLimitTile> {
  late final TextEditingController _ctrl;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.appSettings.speedLimit);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _save() {
    widget.appSettings.setSpeedLimit(_ctrl.text.trim());
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    final scheme  = Theme.of(context).colorScheme;
    final theme   = Theme.of(context);
    final current = widget.appSettings.speedLimit;

    return _SettingCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.speed_outlined, color: scheme.onSurfaceVariant),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Speed limit',
                        style: theme.textTheme.bodyLarge
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    Text(
                      current.isEmpty
                          ? 'Unlimited'
                          : 'Capped at $current (yt-dlp --rate-limit)',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: current.isEmpty ? scheme.onSurfaceVariant : scheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _editing = !_editing;
                  if (_editing) _ctrl.text = widget.appSettings.speedLimit;
                }),
                child: Text(_editing ? 'Cancel' : 'Edit'),
              ),
            ],
          ),
          if (_editing) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    autofocus: true,
                    onSubmitted: (_) => _save(),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[\d.KMGkmg]')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Rate limit',
                      hintText: 'e.g. 2M or 500K — blank = unlimited',
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _save, child: const Text('Save')),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'K = kilobytes/s, M = megabytes/s, G = gigabytes/s. '
              'Example: 2M caps at ~2 MB/s.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}
