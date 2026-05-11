import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../controllers/single_download_controller.dart';
import '../models/download_progress.dart';
import '../models/subtitle_settings.dart';
import '../settings/app_settings.dart';
import '../widgets/download_progress_view.dart';
import '../widgets/format_dropdown.dart';
import '../widgets/metadata_card.dart';
import '../widgets/quality_dropdown.dart';
import '../widgets/subtitle_input.dart';
import '../widgets/trim_input.dart';

/// Single-URL download screen.
class SingleScreen extends StatefulWidget {
  const SingleScreen({super.key, this.controller, this.appSettings});

  final SingleDownloadController? controller;
  final AppSettings? appSettings;

  @override
  State<SingleScreen> createState() => _SingleScreenState();
}

class _SingleScreenState extends State<SingleScreen> {
  late final SingleDownloadController _controller;
  late final TextEditingController _urlController;
  late final TextEditingController _filenameController;
  bool _ownsController = false;
  bool _trimHasError = false;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController();
    _filenameController = TextEditingController();
    if (widget.controller != null) {
      _controller = widget.controller!;
    } else {
      _controller = SingleDownloadController(appSettings: widget.appSettings);
      _ownsController = true;
    }
    // Sync the filename text field when the controller updates it
    // (e.g. after metadata fetch or trim change).
    _controller.addListener(_syncFilenameField);
  }

  /// Build the initial subtitle config off the user's saved defaults so
  /// flipping the master switch on doesn't dump them into "en / srt" when
  /// they configured something else in Settings.
  SubtitleSettings _initialSubtitles() {
    final s = widget.appSettings;
    final base = _controller.subtitles;
    if (base != SubtitleSettings.disabled) return base;
    return SubtitleSettings(
      enabled: false,
      language: s?.defaultSubtitleLang ?? 'en',
      format: s?.defaultSubtitleFormat ?? 'srt',
    );
  }

  void _syncFilenameField() {
    if (_filenameController.text != _controller.customFilename) {
      _filenameController.text = _controller.customFilename;
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_syncFilenameField);
    _urlController.dispose();
    _filenameController.dispose();
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  Future<void> _onFetch() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() => _trimHasError = false);
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
    setState(() => _trimHasError = false);
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
        final selectedOutput = _controller.selectedOutputFormat;
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
                    const SizedBox(height: 12),
                    FormatDropdown(
                      selected: selectedOutput,
                      isAudioOnly: selectedOutput.isAudio,
                      // Drive the per-row size estimate from whichever
                      // quality the user just picked. Switching quality
                      // re-renders the dropdown so the chip updates live.
                      sourceVideoBytes: selected?.fileSize,
                      videoDuration: metadata.duration,
                      enabled: !isDownloading,
                      onChanged: _controller.selectOutputFormat,
                    ),
                    const SizedBox(height: 16),
                    _SliceAndSubtitlesSection(
                      isDownloading: isDownloading,
                      videoDuration: metadata.duration,
                      onTrimChanged: (start, end) =>
                          _controller.setTrim(start: start, end: end),
                      onTrimValidityChanged: (hasError) =>
                          setState(() => _trimHasError = hasError),
                      subtitles: _initialSubtitles(),
                      outputFormat: selectedOutput,
                      metadata: metadata,
                      onSubtitlesChanged: _controller.setSubtitleSettings,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _filenameController,
                      enabled: !isDownloading,
                      onChanged: (value) =>
                          _controller.setCustomFilename(value),
                      decoration: InputDecoration(
                        labelText: 'File name',
                        hintText: 'Enter custom file name',
                        prefixIcon:
                            const Icon(Icons.drive_file_rename_outline),
                        suffixText: '.${_controller.selectedOutputFormat.ext}',
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (progress.phase == DownloadPhase.ready)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton.icon(
                          onPressed: (selected == null || _trimHasError)
                              ? null
                              : _onDownload,
                          icon: const Icon(Icons.download_rounded),
                          label: const Text('Download'),
                        ),
                      ),
                  ],
                  const SizedBox(height: 16),
                  DownloadProgressView(
                    progress: progress,
                    onCancel: _onCancel,
                    onPause: _controller.pause,
                    onResume: _controller.resume,
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

/// Two-column "Slice & subtitles" group.
///
/// Above ~620 dp the trim card and the subtitle card sit side-by-side; below
/// that they stack so neither widget gets squeezed. The header is always
/// shown so the user knows the two cards are conceptually grouped — both
/// are *optional* extras you opt into per download, distinct from the
/// always-present quality / format / filename rows above.
class _SliceAndSubtitlesSection extends StatelessWidget {
  const _SliceAndSubtitlesSection({
    required this.isDownloading,
    required this.videoDuration,
    required this.onTrimChanged,
    this.onTrimValidityChanged,
    required this.subtitles,
    required this.outputFormat,
    required this.onSubtitlesChanged,
    this.metadata,
  });

  final bool isDownloading;
  final Duration? videoDuration;
  final void Function(Duration?, Duration?) onTrimChanged;
  final void Function(bool hasError)? onTrimValidityChanged;
  final SubtitleSettings subtitles;
  final dynamic outputFormat; // OutputFormat — kept dynamic to avoid an extra
  // import alias here; the SubtitleInput widget itself is strongly typed.
  final ValueChanged<SubtitleSettings> onSubtitlesChanged;
  final dynamic metadata; // VideoMetadata?

  static const double _stackThreshold = 620;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget trim() => TrimInput(
          enabled: !isDownloading,
          videoDuration: videoDuration,
          onChanged: onTrimChanged,
          onValidityChanged: onTrimValidityChanged,
        );

    Widget subs() => SubtitleInput(
          enabled: !isDownloading,
          value: subtitles,
          outputFormat: outputFormat,
          metadata: metadata,
          onChanged: onSubtitlesChanged,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 4),
          child: Row(
            children: [
              Icon(Icons.tune, size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                'Slice & subtitles',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < _stackThreshold) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  trim(),
                  const SizedBox(height: 12),
                  subs(),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: trim()),
                const SizedBox(width: 12),
                Expanded(child: subs()),
              ],
            );
          },
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
