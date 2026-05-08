import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../controllers/single_download_controller.dart';
import '../models/download_progress.dart';
import '../widgets/download_progress_view.dart';
import '../widgets/metadata_card.dart';
import '../widgets/quality_dropdown.dart';

/// Single-URL download screen.
///
/// Flow:
/// 1. User pastes a URL → presses Fetch.
/// 2. Spinner while yt-dlp fetches metadata.
/// 3. Metadata card + quality dropdown + Download button.
/// 4. Progress card (live %/speed/ETA) + Cancel.
/// 5. Success card (Open file / Open folder / New download)
///    OR Error card (with retry).
class SingleScreen extends StatefulWidget {
  const SingleScreen({super.key, this.controller});

  /// Optional controller injection for tests. In production we instantiate
  /// our own.
  final SingleDownloadController? controller;

  @override
  State<SingleScreen> createState() => _SingleScreenState();
}

class _SingleScreenState extends State<SingleScreen> {
  late final SingleDownloadController _controller;
  late final TextEditingController _urlController;
  bool _ownsController = false;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController();
    if (widget.controller != null) {
      _controller = widget.controller!;
    } else {
      _controller = SingleDownloadController();
      _ownsController = true;
    }
  }

  @override
  void dispose() {
    _urlController.dispose();
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  Future<void> _onFetch() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    FocusScope.of(context).unfocus();
    await _controller.fetchMetadata(url);
  }

  Future<void> _onDownload() async {
    await _controller.startDownload();
  }

  Future<void> _onCancel() async {
    await _controller.cancel();
  }

  void _onRetry() {
    final m = _controller.metadata;
    if (m != null && _controller.selectedFormat != null) {
      _controller.startDownload();
    } else {
      _onFetch();
    }
  }

  void _onReset() {
    _controller.reset();
    _urlController.clear();
  }

  Future<void> _openFile(String path) async {
    final uri = Uri.file(path);
    if (!await launchUrl(uri)) {
      _showSnack("Couldn't open the file.");
    }
  }

  Future<void> _openFolder(String path) async {
    final dir = File(path).parent.path;
    final uri = Uri.file(dir);
    if (!await launchUrl(uri)) {
      _showSnack("Couldn't open the folder.");
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final progress = _controller.progress;
        final metadata = _controller.metadata;
        final selected = _controller.selectedFormat;
        final isFetching = progress.phase == DownloadPhase.fetchingMetadata;
        final isDownloading = progress.phase == DownloadPhase.downloading;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _Header(),
                  const SizedBox(height: 20),
                  _UrlInputRow(
                    controller: _urlController,
                    onSubmitted: (_) => _onFetch(),
                    enabled: !isFetching && !isDownloading,
                    onFetch: _onFetch,
                    isFetching: isFetching,
                  ),
                  if (metadata != null) ...[
                    const SizedBox(height: 20),
                    MetadataCard(metadata: metadata),
                    const SizedBox(height: 16),
                    QualityDropdown(
                      formats: metadata.formats,
                      selected: selected,
                      enabled: !isDownloading,
                      onChanged: _controller.selectFormat,
                    ),
                    const SizedBox(height: 16),
                    if (progress.phase == DownloadPhase.ready)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton.icon(
                          onPressed: selected == null ? null : _onDownload,
                          icon: const Icon(Icons.download_rounded),
                          label: const Text('Download'),
                        ),
                      ),
                  ],
                  const SizedBox(height: 16),
                  DownloadProgressView(
                    progress: progress,
                    onCancel: _onCancel,
                    onOpenFile: () {
                      if (progress.outputPath != null) {
                        _openFile(progress.outputPath!);
                      }
                    },
                    onOpenFolder: () {
                      if (progress.outputPath != null) {
                        _openFolder(progress.outputPath!);
                      }
                    },
                    onRetry: _onRetry,
                    onReset: _onReset,
                  ),
                  if (progress.phase == DownloadPhase.error && metadata == null)
                    _ErrorBanner(message: progress.errorMessage ?? ''),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Single download',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Paste a YouTube / Instagram / TikTok / X / Facebook URL, '
          'pick a quality, hit download.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _UrlInputRow extends StatelessWidget {
  const _UrlInputRow({
    required this.controller,
    required this.onSubmitted,
    required this.onFetch,
    required this.enabled,
    required this.isFetching,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onFetch;
  final bool enabled;
  final bool isFetching;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            enabled: enabled,
            onSubmitted: onSubmitted,
            keyboardType: TextInputType.url,
            textInputAction: TextInputAction.go,
            decoration: const InputDecoration(
              labelText: 'Video URL',
              hintText: 'https://…',
              prefixIcon: Icon(Icons.link),
            ),
          ),
        ),
        const SizedBox(width: 12),
        FilledButton.icon(
          onPressed: enabled ? onFetch : null,
          icon: isFetching
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.search),
          label: Text(isFetching ? 'Fetching…' : 'Fetch'),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, color: scheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: SelectableText(
                message,
                style: TextStyle(color: scheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
