import 'package:flutter/material.dart';

import '../controllers/download_queue_controller.dart';
import '../models/output_format.dart';
import '../settings/app_settings.dart';
import '../widgets/queue_item_row.dart';

/// Batch download screen.
///
/// Three phases:
///   1. URLs textarea + global format picker → "Preview"
///   2. Preview pass: rows render as metadata resolves. Configure
///      group-folder, then start download.
///   3. Downloading / done with per-item speed/size/cancel/retry.
class BatchScreen extends StatefulWidget {
  const BatchScreen({super.key, required this.appSettings});
  final AppSettings appSettings;

  @override
  State<BatchScreen> createState() => _BatchScreenState();
}

class _BatchScreenState extends State<BatchScreen> {
  late final TextEditingController _urlsCtrl;
  late final TextEditingController _folderCtrl;
  DownloadQueueController? _queueCtrl;
  bool _previewing = false;
  bool _started = false;

  OutputFormat _globalOutput = kDefaultVideoFormat;

  /// Global quality preset: null = Best, -1 = Audio only, positive = max height.
  int? _globalQualityHeight;

  @override
  void initState() {
    super.initState();
    _urlsCtrl = TextEditingController();
    _folderCtrl = TextEditingController();
    _applySettingsDefaults();
    // Re-apply defaults whenever the user changes them in Settings, but only
    // when we're in the initial entry phase (not mid-preview or downloading).
    widget.appSettings.addListener(_onSettingsChanged);
  }

  void _onSettingsChanged() {
    // Only snap to new defaults when no preview/download is in progress,
    // so we don't silently change the format mid-download.
    if (!_previewing && !_started) {
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
  }

  OutputFormat _findFormat(String ext) {
    for (final f in [...kVideoFormats, ...kAudioFormats]) {
      if (f.ext == ext) return f;
    }
    return kDefaultVideoFormat;
  }

  /// Maps settings quality string to the int? used by [_GlobalQualityPicker].
  int? _qualityHeightFromSettings(String q) {
    switch (q) {
      case 'audio': return -1;
      case 'best':  return null;
      default:
        final h = int.tryParse(q.replaceAll('p', ''));
        return h; // null if unparseable → treated as Best
    }
  }

  @override
  void dispose() {
    widget.appSettings.removeListener(_onSettingsChanged);
    _urlsCtrl.dispose();
    _folderCtrl.dispose();
    _queueCtrl?.dispose();
    super.dispose();
  }

  Future<void> _onPreview() async {
    final text = _urlsCtrl.text.trim();
    if (text.isEmpty) return;
    FocusScope.of(context).unfocus();

    final urls = text
        .split(RegExp(r'[\n\r]+'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (urls.isEmpty) return;

    _queueCtrl?.dispose();
    final q = DownloadQueueController(appSettings: widget.appSettings);
    q.addUrls(urls);

    _folderCtrl.text = 'Batch';
    q.setGroupFolder(enabled: widget.appSettings.batchFolder, name: 'Batch');

    q.addListener(_onQueueUpdate);
    _queueCtrl = q;
    _started = false;
    _previewing = true;
    setState(() {});

    await q.previewAll(concurrency: 2);
    if (!mounted) return;

    final firstTitled = q.items.firstWhere(
      (i) => i.metadata?.title.trim().isNotEmpty == true,
      orElse: () => q.items.isNotEmpty ? q.items.first : QueueItem(url: '', title: ''),
    );
    if (firstTitled.metadata != null && _folderCtrl.text == 'Batch') {
      final t = firstTitled.metadata!.title.trim();
      if (t.isNotEmpty) {
        _folderCtrl.text = '$t batch';
        q.setGroupFolder(enabled: q.groupFolderEnabled, name: _folderCtrl.text);
      }
    }

    // Now that metadata is loaded for all items, apply the current quality
    // and format selection so size chips show the correct value immediately,
    // without waiting for the user to touch the quality dropdown.
    q.setGlobalQualityPreset(
      targetHeight: _globalQualityHeight == -1 ? null : _globalQualityHeight,
      audioOnly: _globalQualityHeight == -1,
    );
    q.setGlobalOutputFormat(_globalOutput);

    setState(() => _previewing = false);
  }

  void _onStartDownload() {
    final q = _queueCtrl;
    if (q == null) return;
    q.setGroupFolder(enabled: q.groupFolderEnabled, name: _folderCtrl.text);
    // Apply quality and format right before download starts, using whatever
    // the user selected in the configure card.
    q.setGlobalQualityPreset(
      targetHeight: _globalQualityHeight == -1 ? null : _globalQualityHeight,
      audioOnly: _globalQualityHeight == -1,
    );
    q.setGlobalOutputFormat(_globalOutput);
    setState(() => _started = true);
    q.startAll();
  }

  void _onQueueUpdate() {
    if (mounted) setState(() {});
  }

  void _onReset() {
    _queueCtrl?.dispose();
    _queueCtrl = null;
    _started = false;
    _previewing = false;
    _urlsCtrl.clear();
    _folderCtrl.clear();
    setState(() {});
  }

  void _onBackToInput() {
    _queueCtrl?.dispose();
    _queueCtrl = null;
    _started = false;
    _previewing = false;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasQueue = _queueCtrl != null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Batch download',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Paste a list of URLs (one per line), pick a format, then '
                'hit Preview to fetch thumbnails and customize quality per '
                'video before downloading.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 20),
              if (!hasQueue) _buildInputForm(context),
              if (hasQueue) _buildQueueSection(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputForm(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _urlsCtrl,
          maxLines: 8,
          keyboardType: TextInputType.multiline,
          decoration: const InputDecoration(
            labelText: 'URLs (one per line)',
            hintText:
                'https://youtube.com/watch?v=...\nhttps://tiktok.com/...',
            alignLabelWithHint: true,
            prefixIcon: Padding(
              padding: EdgeInsets.only(bottom: 140),
              child: Icon(Icons.dynamic_feed),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: _onPreview,
            icon: const Icon(Icons.visibility_outlined),
            label: const Text('Preview'),
          ),
        ),
      ],
    );
  }

  Widget _buildQueueSection(BuildContext context) {
    final q = _queueCtrl!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_started)
          _ConfigureCard(
            queue: q,
            previewing: _previewing,
            folderCtrl: _folderCtrl,
            globalOutput: _globalOutput,
            globalQualityHeight: _globalQualityHeight,
            onQualityChanged: (h) {
              setState(() {
                _globalQualityHeight = h;
                if (h == -1 && _globalOutput.category == OutputCategory.video) {
                  _globalOutput = _findFormat(widget.appSettings.defaultAudioFormat);
                } else if (h != -1 && _globalOutput.category == OutputCategory.audio) {
                  _globalOutput = _findFormat(widget.appSettings.defaultFormat);
                }
              });
              // Update per-item selectedFormat so size chips refresh immediately.
              q.setGlobalQualityPreset(
                targetHeight: h == -1 ? null : h,
                audioOnly: h == -1,
              );
              q.setGlobalOutputFormat(_globalOutput);
            },
            onFormatChanged: (f) {
              setState(() => _globalOutput = f);
              q.setGlobalOutputFormat(f);
            },
            onModeChanged: (mode) {
              q.setQualityMode(mode);
              // When switching back to global, re-apply the global format so
              // every row aligns again — setQualityMode only resnaps quality.
              if (mode == QualityMode.global) {
                q.setGlobalOutputFormat(_globalOutput);
              }
            },
            onGroupFolderToggle: (v) {
              q.setGroupFolder(enabled: v, name: _folderCtrl.text);
            },
            onStartDownload: _onStartDownload,
            onBack: _onBackToInput,
          )
        else
          _RunningCard(queue: q, onReset: _onReset),
        const SizedBox(height: 8),
        for (int i = 0; i < q.items.length; i++)
          QueueItemRow(item: q.items[i], queue: q, index: i),
        if (q.items.isEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'No URLs given.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

// ── Global quality picker ──────────────────────────────────────────────────────

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

  final int? selectedHeight;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
    return Row(
      children: [
        if (preset.height != null) ...[
          Icon(
            preset.height == -1 ? Icons.audiotrack_outlined : Icons.videocam_outlined,
            size: 16,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
        ],
        Text(preset.label),
      ],
    );
  }
}

// ── Global format picker ──────────────────────────────────────────────────────

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

// ── Mode toggle (global vs per-item) ────────────────────────────────

/// SegmentedButton that flips the Configure card between
/// [QualityMode.global] (a single Quality + Format dropdown drives every
/// row) and [QualityMode.perItem] (each row exposes its own dropdowns).
class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.mode, required this.onChanged});
  final QualityMode mode;
  final ValueChanged<QualityMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quality mode',
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 6),
        SegmentedButton<QualityMode>(
          segments: const [
            ButtonSegment(
              value: QualityMode.global,
              icon: Icon(Icons.layers_outlined, size: 18),
              label: Text('All same'),
            ),
            ButtonSegment(
              value: QualityMode.perItem,
              icon: Icon(Icons.tune, size: 18),
              label: Text('Per video'),
            ),
          ],
          selected: {mode},
          onSelectionChanged: (s) => onChanged(s.first),
          showSelectedIcon: false,
        ),
      ],
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

// ── Configure card (pre-start) ────────────────────────────────────────────────

class _ConfigureCard extends StatelessWidget {
  const _ConfigureCard({
    required this.queue,
    required this.previewing,
    required this.folderCtrl,
    required this.globalOutput,
    required this.globalQualityHeight,
    required this.onQualityChanged,
    required this.onFormatChanged,
    required this.onModeChanged,
    required this.onGroupFolderToggle,
    required this.onStartDownload,
    required this.onBack,
  });

  final DownloadQueueController queue;
  final bool previewing;
  final TextEditingController folderCtrl;
  final OutputFormat globalOutput;
  final int? globalQualityHeight;
  final ValueChanged<int?> onQualityChanged;
  final ValueChanged<OutputFormat> onFormatChanged;
  final ValueChanged<QualityMode> onModeChanged;
  final ValueChanged<bool> onGroupFolderToggle;
  final VoidCallback onStartDownload;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final total = queue.items.length;
    final previewed = queue.items
        .where((i) => i.metadata != null || i.previewError != null)
        .length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  previewing ? Icons.hourglass_top : Icons.tune,
                  color: scheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    previewing
                        ? 'Previewing ($previewed / $total)…'
                        : 'Configure download ($total videos)',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            if (previewing) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: total > 0 ? previewed / total : null,
                  minHeight: 4,
                  backgroundColor: scheme.surfaceContainerHighest,
                ),
              ),
            ],
            const SizedBox(height: 12),
            // ── Mode toggle (global vs per-item) ─────────────────────────
            ListenableBuilder(
              listenable: queue,
              builder: (_, __) => _ModeToggle(
                mode: queue.qualityMode,
                onChanged: onModeChanged,
              ),
            ),
            const SizedBox(height: 12),
            // ── Global pickers — only when mode == global ────────────────
            ListenableBuilder(
              listenable: queue,
              builder: (_, __) {
                if (queue.qualityMode != QualityMode.global) {
                  return const SizedBox.shrink();
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _GlobalQualityPicker(
                      selectedHeight: globalQualityHeight,
                      onChanged: onQualityChanged,
                    ),
                    const SizedBox(height: 12),
                    _GlobalFormatPicker(
                      globalOutput: globalOutput,
                      isAudioOnly: globalQualityHeight == -1,
                      onChanged: onFormatChanged,
                    ),
                    const SizedBox(height: 12),
                  ],
                );
              },
            ),
            ListenableBuilder(
              listenable: queue,
              builder: (_, __) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: queue.groupFolderEnabled,
                    onChanged: onGroupFolderToggle,
                    title: const Text('Save into a subfolder'),
                    subtitle: Text(
                      queue.groupFolderEnabled
                          ? 'Files go into Down4More / <subfolder>'
                          : 'Files go directly into Down4More',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                  if (queue.groupFolderEnabled)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: TextField(
                        controller: folderCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Folder name',
                          isDense: true,
                          prefixIcon: Icon(Icons.folder_outlined),
                        ),
                        onChanged: (v) =>
                            queue.setGroupFolder(enabled: true, name: v),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton.icon(
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back to URLs'),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed:
                      previewing || total == 0 ? null : onStartDownload,
                  icon: const Icon(Icons.download_rounded),
                  label: Text('Download $total items'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Running card ──────────────────────────────────────────────────────────────

class _RunningCard extends StatelessWidget {
  const _RunningCard({required this.queue, required this.onReset});
  final DownloadQueueController queue;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final done = queue.finishedCount;
    final total = queue.totalCount;
    final errors = queue.errorCount;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  queue.isRunning
                      ? Icons.downloading_rounded
                      : Icons.check_circle_outline,
                  color: scheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  queue.isRunning
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
                if (queue.isRunning)
                  TextButton.icon(
                    onPressed: () => queue.cancelAll(),
                    icon: const Icon(Icons.close),
                    label: const Text('Cancel all'),
                  ),
                if (!queue.isRunning && errors > 0)
                  FilledButton.tonal(
                    onPressed: () => queue.retryFailed(),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.refresh, size: 18),
                        SizedBox(width: 6),
                        Text('Retry failed'),
                      ],
                    ),
                  ),
                if (!queue.isRunning)
                  TextButton.icon(
                    onPressed: onReset,
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('New batch'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
