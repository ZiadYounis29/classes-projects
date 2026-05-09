import 'package:flutter/material.dart';

import '../controllers/download_queue_controller.dart';
import '../models/output_format.dart';
import '../settings/app_settings.dart';
import '../widgets/queue_item_row.dart';

/// Batch download screen.
///
/// Three phases:
///   1. URLs textarea → "Preview" (renamed from "Download all")
///   2. Preview pass: rows render as `previewAll(concurrency:2)` resolves
///      each item's metadata. The user can adjust per-item dropdowns +
///      group-folder before kicking off the queue.
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

  @override
  void initState() {
    super.initState();
    _urlsCtrl = TextEditingController();
    _folderCtrl = TextEditingController();
    _globalOutput = _findFormat(widget.appSettings.defaultFormat);
  }

  OutputFormat _findFormat(String ext) {
    for (final f in [...kVideoFormats, ...kAudioFormats]) {
      if (f.ext == ext) return f;
    }
    return kDefaultVideoFormat;
  }

  @override
  void dispose() {
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
    q.setGlobalOutputFormat(_globalOutput);

    // Default group-folder OFF for batch (user explicitly opts in). Pre-fill
    // a sensible name based on the first URL — once preview lands we'll
    // upgrade it to the first item's title.
    _folderCtrl.text = 'Batch';
    q.setGroupFolder(enabled: false, name: 'Batch');

    q.addListener(_onQueueUpdate);
    _queueCtrl = q;
    _started = false;
    _previewing = true;
    setState(() {});

    // Eager metadata fetch for batch (vs. lazy fetch for playlists).
    await q.previewAll(concurrency: 2);
    if (!mounted) return;

    // Upgrade default folder name to "<first title> batch" once we know it.
    final firstTitled = q.items.firstWhere(
      (i) => i.metadata?.title.trim().isNotEmpty == true,
      orElse: () => q.items.isNotEmpty ? q.items.first : QueueItem(url: '', title: ''),
    );
    if (firstTitled.metadata != null && _folderCtrl.text == 'Batch') {
      final t = firstTitled.metadata!.title.trim();
      if (t.isNotEmpty) {
        _folderCtrl.text = '$t batch';
        // Don't auto-enable; the toggle stays OFF unless the user flips it.
        q.setGroupFolder(enabled: q.groupFolderEnabled, name: _folderCtrl.text);
      }
    }

    setState(() => _previewing = false);
  }

  void _onStartDownload() {
    final q = _queueCtrl;
    if (q == null) return;
    q.setGroupFolder(enabled: q.groupFolderEnabled, name: _folderCtrl.text);
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
                'Paste a list of URLs (one per line). Hit Preview to fetch '
                'thumbnails and customize quality / format per video, then '
                'download them all. Concurrency comes from Settings.',
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
            globalOutput: _globalOutput,
            onGlobalOutputChanged: (f) {
              setState(() => _globalOutput = f);
              q.setGlobalOutputFormat(f);
            },
            folderCtrl: _folderCtrl,
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

/// Card shown above the queue while the user is configuring (pre-start).
class _ConfigureCard extends StatelessWidget {
  const _ConfigureCard({
    required this.queue,
    required this.previewing,
    required this.globalOutput,
    required this.onGlobalOutputChanged,
    required this.folderCtrl,
    required this.onGroupFolderToggle,
    required this.onStartDownload,
    required this.onBack,
  });

  final DownloadQueueController queue;
  final bool previewing;
  final OutputFormat globalOutput;
  final ValueChanged<OutputFormat> onGlobalOutputChanged;
  final TextEditingController folderCtrl;
  final ValueChanged<bool> onGroupFolderToggle;
  final VoidCallback onStartDownload;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final total = queue.items.length;
    final previewed =
        queue.items.where((i) => i.metadata != null || i.previewError != null)
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
            DropdownButtonFormField<String>(
              isDense: true,
              value: globalOutput.ext,
              decoration: const InputDecoration(
                labelText: 'Default format for all videos',
                prefixIcon: Icon(Icons.movie_outlined),
              ),
              items: [
                for (final f in [...kVideoFormats, ...kAudioFormats])
                  DropdownMenuItem(value: f.ext, child: Text(f.label)),
              ],
              onChanged: (ext) {
                if (ext == null) return;
                final f = [...kVideoFormats, ...kAudioFormats]
                    .firstWhere((x) => x.ext == ext);
                onGlobalOutputChanged(f);
              },
            ),
            const SizedBox(height: 12),
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

/// Card shown above the queue once download has started.
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
