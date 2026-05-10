import 'package:flutter/material.dart';

import '../controllers/download_queue_controller.dart';
import '../controllers/playlist_controller.dart';
import '../models/output_format.dart';
import '../settings/app_settings.dart';
import '../widgets/queue_item_row.dart';

/// Playlist download screen.
///
/// Two phases:
///   1. URL input → Fetch
///   2. Selection list with global format control + Download button on the
///      same screen. Once started: per-item progress rows.
class PlaylistScreen extends StatefulWidget {
  const PlaylistScreen({super.key, required this.appSettings});
  final AppSettings appSettings;

  @override
  State<PlaylistScreen> createState() => _PlaylistScreenState();
}

class _PlaylistScreenState extends State<PlaylistScreen> {
  late final PlaylistController _playlistCtrl;
  late final TextEditingController _urlCtrl;
  late final TextEditingController _folderCtrl;
  DownloadQueueController? _queueCtrl;

  bool _started = false;

  /// Whether to save downloads into a named subfolder (default: true for playlists).
  bool _groupFolderEnabled = true; // overridden in initState from appSettings

  /// Global output format applied to every queue item.
  OutputFormat _globalOutput = kDefaultVideoFormat;

  /// Global quality preset applied to every queue item.
  /// null = Best available, positive int = max height, -1 = audio only.
  int? _globalQualityHeight; // null = best

  @override
  void initState() {
    super.initState();
    _playlistCtrl = PlaylistController();
    _urlCtrl = TextEditingController();
    _folderCtrl = TextEditingController();
    _applySettingsDefaults();
    widget.appSettings.addListener(_onSettingsChanged);
  }

  void _onSettingsChanged() {
    if (!_started) {
      setState(_applySettingsDefaults);
    }
  }

  void _applySettingsDefaults() {
    _globalOutput = _findFormat(widget.appSettings.defaultFormat);
    _globalQualityHeight = _qualityHeightFromSettings(widget.appSettings.defaultQuality);
    // If default quality is audio, make sure format is audio too.
    if (_globalQualityHeight == -1 && _globalOutput.category == OutputCategory.video) {
      _globalOutput = _findFormat(widget.appSettings.defaultAudioFormat);
    }
    _groupFolderEnabled = widget.appSettings.playlistFolder;
  }

  OutputFormat _findFormat(String ext) {
    for (final f in [...kVideoFormats, ...kAudioFormats]) {
      if (f.ext == ext) return f;
    }
    return kDefaultVideoFormat;
  }

  int? _qualityHeightFromSettings(String q) {
    switch (q) {
      case 'audio': return -1;
      case 'best':  return null;
      default:
        final h = int.tryParse(q.replaceAll('p', ''));
        return h;
    }
  }

  @override
  void dispose() {
    widget.appSettings.removeListener(_onSettingsChanged);
    _urlCtrl.dispose();
    _folderCtrl.dispose();
    _playlistCtrl.dispose();
    _queueCtrl?.dispose();
    super.dispose();
  }

  Future<void> _onFetch() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) return;
    FocusScope.of(context).unfocus();
    _queueCtrl?.dispose();
    _queueCtrl = null;
    _started = false;
    _folderCtrl.clear();
    await _playlistCtrl.fetchPlaylist(url);
    // Pre-populate the folder name with the playlist title once fetched.
    if (_playlistCtrl.playlistTitle?.trim().isNotEmpty == true) {
      _folderCtrl.text = _playlistCtrl.playlistTitle!.trim();
    } else {
      _folderCtrl.text = 'Playlist';
    }
    if (mounted) setState(() {});
  }

  void _onStartDownload() {
    final entries = _playlistCtrl.selectedEntries;
    if (entries.isEmpty) return;

    _queueCtrl?.dispose();
    final q = DownloadQueueController(appSettings: widget.appSettings);
    q.addEntries(entries);
    q.setGlobalOutputFormat(_globalOutput);

    // Use whatever the user has set in the folder controls.
    final folderName = _folderCtrl.text.trim().isNotEmpty
        ? _folderCtrl.text.trim()
        : (_playlistCtrl.playlistTitle?.trim().isNotEmpty == true
            ? _playlistCtrl.playlistTitle!
            : 'Playlist');
    _folderCtrl.text = folderName;
    q.setGroupFolder(enabled: _groupFolderEnabled, name: folderName);

    // Apply the global quality preset after metadata is attached to items.
    q.setGlobalQualityPreset(
      targetHeight: _globalQualityHeight == -1 ? null : _globalQualityHeight,
      audioOnly: _globalQualityHeight == -1,
    );

    q.addListener(_onQueueUpdate);
    _queueCtrl = q;
    _started = true;
    setState(() {});
    q.startAll();
  }

  void _onQueueUpdate() {
    if (mounted) setState(() {});
  }

  void _onReset() {
    _playlistCtrl.reset();
    _queueCtrl?.dispose();
    _queueCtrl = null;
    _started = false;
    _applySettingsDefaults();
    _urlCtrl.clear();
    _folderCtrl.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _playlistCtrl,
      builder: (context, _) {
        final phase = _playlistCtrl.phase;
        final isFetching = phase == PlaylistPhase.fetching;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(context),
                  const SizedBox(height: 20),
                  _buildUrlRow(context, isFetching),
                  if (phase == PlaylistPhase.error) ...[
                    const SizedBox(height: 16),
                    _buildErrorBanner(context),
                  ],
                  if (phase == PlaylistPhase.ready && !_started) ...[
                    const SizedBox(height: 16),
                    _buildSelectionControls(context),
                    const SizedBox(height: 8),
                    _buildEntryList(context),
                  ],
                  if (_started && _queueCtrl != null)
                    _buildRunningSection(context),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Playlist',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Paste a playlist URL, pick which videos you want, set format, '
          'then download them all at once.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildUrlRow(BuildContext context, bool isFetching) {
    final enabled = !isFetching && !_started;
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _urlCtrl,
            enabled: enabled,
            onSubmitted: (_) => _onFetch(),
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.go,
            decoration: const InputDecoration(
              labelText: 'Playlist URL',
              hintText: 'https://youtube.com/playlist?list=...',
              prefixIcon: Icon(Icons.list_alt),
            ),
          ),
        ),
        const SizedBox(width: 12),
        FilledButton.icon(
          onPressed: enabled ? _onFetch : null,
          icon: isFetching
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.search),
          label: Text(isFetching ? 'Fetching...' : 'Fetch'),
        ),
      ],
    );
  }

  Widget _buildErrorBanner(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: scheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _playlistCtrl.errorMessage ?? 'Unknown error',
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
            TextButton(onPressed: _onFetch, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  /// Combined selection count + global quality + global format + download button.
  Widget _buildSelectionControls(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final total = _playlistCtrl.entries.length;
    final selected = _playlistCtrl.selectedCount;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Selection count + select/deselect all ──────────────────
            Row(
              children: [
                Text(
                  '$selected of $total selected',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: selected == total
                      ? _playlistCtrl.deselectAll
                      : _playlistCtrl.selectAll,
                  child: Text(
                      selected == total ? 'Deselect all' : 'Select all'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // ── Global quality ─────────────────────────────────────────
            _GlobalQualityPicker(
              selectedHeight: _globalQualityHeight,
              onChanged: (h) {
                setState(() {
                  _globalQualityHeight = h;
                  // Mirror selectFormat() in SingleDownloadController:
                  // snap the output format when switching categories.
                  if (h == -1 && _globalOutput.category == OutputCategory.video) {
                    _globalOutput = _findFormat(widget.appSettings.defaultAudioFormat);
                  } else if (h != -1 && _globalOutput.category == OutputCategory.audio) {
                    _globalOutput = _findFormat(widget.appSettings.defaultFormat).isVideo
                        ? _findFormat(widget.appSettings.defaultFormat)
                        : kDefaultVideoFormat;
                  }
                });
              },
            ),
            const SizedBox(height: 12),
            // ── Global format ──────────────────────────────────────────
            _GlobalFormatPicker(
              globalOutput: _globalOutput,
              isAudioOnly: _globalQualityHeight == -1,
              onChanged: (f) => setState(() => _globalOutput = f),
            ),
            const SizedBox(height: 12),
            // ── Folder settings ────────────────────────────────────────
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _groupFolderEnabled,
              onChanged: (v) => setState(() => _groupFolderEnabled = v),
              title: const Text('Save into a subfolder'),
              subtitle: Text(
                _groupFolderEnabled
                    ? 'Files go into Down4More / <subfolder>'
                    : 'Files go directly into Down4More',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              visualDensity: VisualDensity.compact,
            ),
            if (_groupFolderEnabled) ...[
              const SizedBox(height: 6),
              TextField(
                controller: _folderCtrl,
                decoration: const InputDecoration(
                  labelText: 'Folder name',
                  isDense: true,
                  prefixIcon: Icon(Icons.folder_outlined),
                ),
              ),
            ],
            const SizedBox(height: 16),
            // ── Download button ────────────────────────────────────────
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: selected > 0 ? _onStartDownload : null,
                icon: const Icon(Icons.download_rounded),
                label: Text('Download ($selected)'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEntryList(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final entries = _playlistCtrl.entries;
    final selectedIndices = _playlistCtrl.selectedIndices;

    return Column(
      children: [
        for (int i = 0; i < entries.length; i++)
          Card(
            margin: const EdgeInsets.only(bottom: 4),
            child: InkWell(
              onTap: () => _playlistCtrl.toggleSelection(i),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Checkbox(
                      value: selectedIndices.contains(i),
                      onChanged: (_) => _playlistCtrl.toggleSelection(i),
                    ),
                    const SizedBox(width: 8),
                    if (entries[i].thumbnailUrl != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.network(
                          entries[i].thumbnailUrl!,
                          width: 80,
                          height: 45,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: 80,
                            height: 45,
                            color: scheme.surfaceContainerHighest,
                            child: Icon(Icons.movie_outlined,
                                color: scheme.onSurfaceVariant),
                          ),
                        ),
                      )
                    else
                      Container(
                        width: 80,
                        height: 45,
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(Icons.movie_outlined,
                            color: scheme.onSurfaceVariant),
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entries[i].title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (entries[i].duration != null)
                            Text(
                              _formatDuration(entries[i].duration!),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      '#${i + 1}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildRunningSection(BuildContext context) {
    final q = _queueCtrl!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return ListenableBuilder(
      listenable: q,
      builder: (context, _) {
        final done = q.finishedCount;
        final total = q.totalCount;
        final errors = q.errorCount;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          q.isRunning
                              ? Icons.downloading_rounded
                              : Icons.check_circle_outline,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          q.isRunning
                              ? 'Downloading ($done / $total)...'
                              : 'Finished ($done / $total)',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (errors > 0) ...[
                          const SizedBox(width: 8),
                          Chip(
                            label: Text('$errors failed'),
                            backgroundColor: scheme.errorContainer,
                            side: BorderSide.none,
                            visualDensity: VisualDensity.compact,
                            labelStyle: TextStyle(
                              color: scheme.onErrorContainer,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: total > 0 ? done / total : null,
                        minHeight: 6,
                        backgroundColor: scheme.surfaceContainerHighest,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (q.isRunning)
                          TextButton.icon(
                            onPressed: () => q.cancelAll(),
                            icon: const Icon(Icons.close),
                            label: const Text('Cancel all'),
                          ),
                        if (!q.isRunning && errors > 0)
                          FilledButton.tonal(
                            onPressed: () => q.retryFailed(),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.refresh, size: 18),
                                SizedBox(width: 6),
                                Text('Retry failed'),
                              ],
                            ),
                          ),
                        if (!q.isRunning)
                          TextButton.icon(
                            onPressed: _onReset,
                            icon: const Icon(Icons.arrow_back),
                            label: const Text('New playlist'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            for (int i = 0; i < q.items.length; i++)
              QueueItemRow(item: q.items[i], queue: q, index: i),
          ],
        );
      },
    );
  }
}

// ── Global quality picker ─────────────────────────────────────────────────────

/// Quality presets expressed as max-height values.
/// null  = Best available
/// -1    = Audio only
const _kQualityPresets = [
  (label: 'Best available', height: null),
  (label: '4K (2160p)', height: 2160),
  (label: '1440p', height: 1440),
  (label: '1080p', height: 1080),
  (label: '720p', height: 720),
  (label: '480p', height: 480),
  (label: '360p', height: 360),
  (label: '240p', height: 240),
  (label: '144p', height: 144),
  (label: 'Audio only', height: -1),
];

class _GlobalQualityPicker extends StatelessWidget {
  const _GlobalQualityPicker({
    required this.selectedHeight,
    required this.onChanged,
  });

  /// null = Best, -1 = Audio only, positive = max height.
  final int? selectedHeight;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Normalise: if selectedHeight isn't in the preset list, treat as null.
    final validHeights = _kQualityPresets.map((p) => p.height).toSet();
    final effectiveHeight =
        validHeights.contains(selectedHeight) ? selectedHeight : null;

    return DropdownButtonFormField<int?>(
      value: effectiveHeight,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Quality for all videos',
        prefixIcon: Icon(Icons.high_quality_outlined),
      ),
      items: [
        for (final preset in _kQualityPresets)
          DropdownMenuItem<int?>(
            value: preset.height,
            child: _QualityPresetRow(preset: preset, scheme: scheme),
          ),
      ],
      onChanged: (h) => onChanged(h),
    );
  }
}

class _QualityPresetRow extends StatelessWidget {
  const _QualityPresetRow({required this.preset, required this.scheme});
  final ({String label, int? height}) preset;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    IconData icon;
    if (preset.height == null) {
      icon = Icons.star_outlined;
    } else if (preset.height == -1) {
      icon = Icons.audiotrack_outlined;
    } else {
      icon = Icons.videocam_outlined;
    }

    return Row(
      children: [
        Icon(icon, size: 16, color: scheme.onSurfaceVariant),
        const SizedBox(width: 10),
        Text(preset.label),
      ],
    );
  }
}

// ── Global format picker (shared) ─────────────────────────────────────────────

class _GlobalFormatPicker extends StatelessWidget {
  const _GlobalFormatPicker({
    required this.globalOutput,
    required this.isAudioOnly,
    required this.onChanged,
  });

  final OutputFormat globalOutput;
  final bool isAudioOnly;
  final ValueChanged<OutputFormat> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Mirror exactly what FormatDropdown does in the Single screen:
    // show only the relevant category based on the current quality selection.
    final formats = isAudioOnly ? kAudioFormats : kVideoFormats;
    final effectiveSelected =
        formats.contains(globalOutput) ? globalOutput : formats.first;

    return DropdownButtonFormField<String>(
      value: effectiveSelected.ext,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Format for all videos',
        prefixIcon: Icon(
          isAudioOnly ? Icons.audiotrack_outlined : Icons.movie_outlined,
        ),
      ),
      items: [
        for (final f in formats)
          DropdownMenuItem(
            value: f.ext,
            child: _FormatRow(format: f, scheme: scheme),
          ),
      ],
      onChanged: (ext) {
        if (ext == null) return;
        final f = formats.firstWhere((x) => x.ext == ext);
        onChanged(f);
      },
    );
  }
}
class _FormatRow extends StatelessWidget {
  const _FormatRow({required this.format, required this.scheme});
  final OutputFormat format;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: scheme.secondaryContainer,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            format.ext.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: scheme.onSecondaryContainer,
              letterSpacing: 0.5,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            format.note ?? format.label,
            style: const TextStyle(fontSize: 13),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

String _formatDuration(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  if (h > 0) return '$h:${two(m)}:${two(s)}';
  return '$m:${two(s)}';
}
