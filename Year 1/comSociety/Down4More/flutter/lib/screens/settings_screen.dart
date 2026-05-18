import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/subtitle_settings.dart';
import '../settings/app_settings.dart';
import '../theme/theme_controller.dart';
import '../widgets/bidi_text_field.dart';
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

            // ── Defaults ────────────────────────────────────────────────────
            // Format, quality, and concurrency applied to new downloads.
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

            // ── Downloads ───────────────────────────────────────────────────
            // Folder location, file handling, output organisation, notifications.
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
            const SizedBox(height: 8),
            _SwitchTile(
              icon: Icons.folder_copy_outlined,
              title: 'Batch: save into subfolder',
              subtitle: 'Create a named subfolder for each batch by default',
              value: appSettings.batchFolder,
              onChanged: appSettings.setBatchFolder,
            ),
            const SizedBox(height: 8),
            _SwitchTile(
              icon: Icons.playlist_add_check_outlined,
              title: 'Playlist: save into subfolder',
              subtitle: 'Create a named subfolder for each playlist by default',
              value: appSettings.playlistFolder,
              onChanged: appSettings.setPlaylistFolder,
            ),
            const SizedBox(height: 8),
            _SwitchTile(
              icon: Icons.label_outline,
              title: 'Append quality to filename',
              subtitle:
                  'Adds the quality label to the filename (e.g. "Title [1080p]"). '
                  'In Single mode, updates the name field live as you change quality.',
              value: appSettings.appendQualityToFilename,
              onChanged: appSettings.setAppendQualityToFilename,
            ),
            const SizedBox(height: 8),
            _SwitchTile(
              icon: Icons.notifications_active_outlined,
              title: 'Desktop notifications',
              subtitle: 'Show an OS notification when a download completes',
              value: appSettings.notificationsEnabled,
              onChanged: appSettings.setNotificationsEnabled,
            ),
            const SizedBox(height: 32),

            // ── Queue behaviour ──────────────────────────────────────────────
            // Controls what happens when items are paused or the queue shifts.
            const _SectionHeader(
                icon: Icons.queue_outlined, title: 'Queue behaviour'),
            const SizedBox(height: 12),
            _SwitchTile(
              icon: Icons.skip_next_outlined,
              title: 'Single pause: start next in queue',
              subtitle:
                  'When you pause a single item, automatically start the '
                  'next idle item in the queue to fill the freed slot.',
              value: appSettings.pauseSingleStartsNext,
              onChanged: appSettings.setPauseSingleStartsNext,
            ),
            const SizedBox(height: 8),
            _SwitchTile(
              icon: Icons.playlist_play_outlined,
              title: 'Pause all: start next in queue',
              subtitle:
                  'When you pause all items, automatically start the next '
                  'idle items to fill the freed slots.',
              value: appSettings.pauseAllStartsNext,
              onChanged: appSettings.setPauseAllStartsNext,
            ),
            const SizedBox(height: 32),

            // ── Subtitles ───────────────────────────────────────────────────
            const _SectionHeader(
                icon: Icons.closed_caption_outlined, title: 'Subtitles'),
            const SizedBox(height: 12),
            _SubtitleLanguageTile(appSettings: appSettings),
            const SizedBox(height: 8),
            _DropdownTile<String>(
              icon: Icons.subtitles_outlined,
              title: 'Default subtitle format',
              subtitle:
                  'srt is the universal default; vtt for web; ass for styling',
              value: kSubtitleFormats.any((f) => f.ext == appSettings.defaultSubtitleFormat)
                  ? appSettings.defaultSubtitleFormat
                  : kDefaultSubtitleFormat.ext,
              items: [
                for (final f in kSubtitleFormats)
                  DropdownMenuItem<String>(
                    value: f.ext,
                    child: Text(f.label),
                  ),
              ],
              onChanged: appSettings.setDefaultSubtitleFormat,
            ),
            const SizedBox(height: 8),
            _SwitchTile(
              icon: Icons.verified_outlined,
              title: 'Prefer manual captions over auto',
              subtitle:
                  'In Playlist & Batch: when you select auto-captions but a '
                  'manual track exists for the same language, use the manual '
                  'version instead — it is usually more accurate.',
              value: appSettings.preferManualOverAuto,
              onChanged: appSettings.setPreferManualOverAuto,
            ),
            const SizedBox(height: 32),

            // ── Network ─────────────────────────────────────────────────────
            // Speed cap and automatic retry on failure.
            const _SectionHeader(icon: Icons.cloud_outlined, title: 'Network'),
            const SizedBox(height: 12),
            _SpeedLimitTile(appSettings: appSettings),
            const SizedBox(height: 8),
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
    // On desktop, the OS folder picker is far friendlier than asking the
    // user to type an absolute path. Android's SAF picker returns a
    // `content://` URI that yt-dlp can't write to, so we fall through to
    // the manual-entry dialog (with platform-aware copy) on Android.
    final useNativePicker = !kIsWeb &&
        (Platform.isLinux || Platform.isMacOS || Platform.isWindows);
    if (useNativePicker) {
      try {
        final picked = await FilePicker.getDirectoryPath(
          dialogTitle: 'Choose download folder',
          initialDirectory: appSettings.downloadDir.isNotEmpty
              ? appSettings.downloadDir
              : null,
        );
        if (picked != null && picked.isNotEmpty) {
          await appSettings.setDownloadDir(picked);
        }
        return;
      } catch (_) {
        // Native picker missing or failed (e.g. Linux without
        // zenity/kdialog). Fall back to the manual dialog so the user can
        // still set a folder by typing the path.
      }
    }

    if (!context.mounted) return;
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
    final isAndroid = !kIsWeb && Platform.isAndroid;

    // Android's destination is always `Movies/Down4More/` (or
    // `Music/Down4More/`) via MediaStore — the `downloadDir` setting
    // controls the scratch dir yt-dlp writes into before the export. Be
    // upfront about that so users don't think they're customising the
    // gallery destination.
    final defaultLabel = isAndroid
        ? 'Default — app scratch dir, exported to Movies/Down4More/'
        : 'Default — ~/Downloads/Down4More';

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
                  current.isEmpty ? defaultLabel : current,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontFamily: current.isEmpty ? null : 'monospace',
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (isAndroid) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Finished files always appear under '
                    'Movies/Down4More (or Music/Down4More for audio). '
                    'This setting only changes the scratch folder.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              FilledButton.tonalIcon(
                onPressed: () => _pick(context),
                icon: Icon(
                  isAndroid ? Icons.edit_outlined : Icons.folder_open_outlined,
                  size: 16,
                ),
                label: Text(isAndroid ? 'Change' : 'Browse'),
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
    final isAndroid = !kIsWeb && Platform.isAndroid;
    final hint = isAndroid
        ? '/storage/emulated/0/Download/Down4More'
        : (Platform.isWindows
            ? 'C:\\Users\\you\\Videos'
            : '/home/you/Videos');

    return AlertDialog(
      title: const Text('Download folder'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isAndroid)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Type the absolute path to your scratch folder. The '
                  'finished file is still copied to Movies/Down4More/ '
                  '(or Music/Down4More/) so it shows up in the gallery.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            BidiTextField(
              controller: _ctrl,
              autofocus: true,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Absolute path',
                hintText: hint,
                errorText: _error,
                prefixIcon: const Icon(Icons.folder_outlined),
              ),
            ),
          ],
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
    final videoVal = _videoExts.contains(appSettings.defaultFormat) ? appSettings.defaultFormat : 'mp4';
    final audioVal = _audioExts.contains(appSettings.defaultAudioFormat) ? appSettings.defaultAudioFormat : 'm4a';

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
                  onChanged: (v) { if (v != null) appSettings.setDefaultAudioFormat(v); },
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

// ── Subtitle language tile ────────────────────────────────────────────────────

/// Default subtitle language picker. Mirrors the in-flow [SubtitleInput]
/// language row: a dropdown of the 12 common IETF tags plus an "Other…"
/// option that reveals a free-form text field for anything more exotic
/// (regional variants like `pt-BR`, alternate scripts like `zh-Hant`,
/// uploader-original tracks like `en-orig`, etc.).
class _SubtitleLanguageTile extends StatefulWidget {
  const _SubtitleLanguageTile({required this.appSettings});
  final AppSettings appSettings;

  @override
  State<_SubtitleLanguageTile> createState() => _SubtitleLanguageTileState();
}

class _SubtitleLanguageTileState extends State<_SubtitleLanguageTile> {
  static const String _other = '__other__';
  late final TextEditingController _customCtrl;

  @override
  void initState() {
    super.initState();
    _customCtrl = TextEditingController(
      text: _isCustom(widget.appSettings.defaultSubtitleLang)
          ? widget.appSettings.defaultSubtitleLang
          : '',
    );
  }

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  bool _isCustom(String code) =>
      code.isNotEmpty && !kSubtitleLanguages.any((l) => l.code == code);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final current = widget.appSettings.defaultSubtitleLang;
    final selected = _isCustom(current) ? _other : current;

    return _SettingCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.language_rounded, color: scheme.onSurfaceVariant),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Default subtitle language',
                        style: theme.textTheme.bodyLarge
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    Text(
                      'Used when you flip on subtitles in Single, Batch, or Playlist',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: kSubtitleLanguages.any((l) => l.code == selected) ||
                    selected == _other
                ? selected
                : kSubtitleLanguages.first.code,
            isExpanded: true,
            decoration: const InputDecoration(
              isDense: true,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            items: [
              for (final l in kSubtitleLanguages)
                DropdownMenuItem(value: l.code, child: Text(l.label)),
              const DropdownMenuItem(value: _other, child: Text('Other…')),
            ],
            onChanged: (v) {
              if (v == null) return;
              if (v == _other) {
                final raw = _customCtrl.text.trim();
                widget.appSettings.setDefaultSubtitleLang(raw);
              } else {
                widget.appSettings.setDefaultSubtitleLang(v);
              }
              setState(() {});
            },
          ),
          if (selected == _other) ...[
            const SizedBox(height: 8),
            BidiTextField(
              controller: _customCtrl,
              decoration: const InputDecoration(
                labelText: 'IETF language tag',
                hintText: 'e.g. pt-BR, zh-Hant, en-orig',
                isDense: true,
                prefixIcon: Icon(Icons.translate_rounded),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              onChanged: (v) =>
                  widget.appSettings.setDefaultSubtitleLang(v.trim()),
            ),
          ],
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
