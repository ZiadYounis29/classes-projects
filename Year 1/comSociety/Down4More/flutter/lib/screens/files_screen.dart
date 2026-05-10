import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../settings/app_settings.dart';

/// Downloaded-files browser.
///
/// Lists all files and folders in the configured download directory.
/// Folders can be tapped to navigate into them; a breadcrumb trail
/// lets the user navigate back. Both files and folders can be deleted
/// (folders are removed recursively after a confirmation dialog that
/// clearly states all contents will be lost).
class FilesScreen extends StatefulWidget {
  const FilesScreen({super.key, required this.appSettings});
  final AppSettings appSettings;

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  List<FileSystemEntity>? _entities;
  /// Root download directory (never changes once resolved).
  String? _rootDir;
  /// Currently viewed directory (changes as user navigates into folders).
  String? _currentDir;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles({String? dir}) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final root = await _resolveDir();
      _rootDir ??= root;
      final target = dir ?? _currentDir ?? root;
      _currentDir = target;

      final d = Directory(target);
      if (!await d.exists()) {
        await d.create(recursive: true);
      }

      final entities = await d.list().toList();
      entities.sort((a, b) {
        // Folders first, then files; within each group sort newest-first.
        final aIsDir = a is Directory;
        final bIsDir = b is Directory;
        if (aIsDir != bIsDir) return aIsDir ? -1 : 1;
        final aStat = a.statSync();
        final bStat = b.statSync();
        return bStat.modified.compareTo(aStat.modified);
      });

      setState(() {
        _entities = entities;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<String> _resolveDir() async {
    final custom = widget.appSettings.downloadDir;
    if (custom.isNotEmpty) return custom;

    Directory? base;
    try {
      base = await getDownloadsDirectory();
    } catch (_) {
      base = null;
    }
    if (base == null) {
      final home = Platform.environment['HOME'] ??
          Platform.environment['USERPROFILE'];
      if (home != null) {
        base = Directory(p.join(home, 'Downloads'));
      } else {
        base = Directory.current;
      }
    }
    return p.join(base.path, 'Down4More');
  }

  /// Navigate into a subfolder.
  void _enterFolder(String path) => _loadFiles(dir: path);

  /// Navigate up one level, stopping at the root download directory.
  void _goUp() {
    if (_currentDir == null || _currentDir == _rootDir) return;
    _loadFiles(dir: p.dirname(_currentDir!));
  }

  bool get _isAtRoot => _currentDir == null || _currentDir == _rootDir;

  /// Breadcrumb segments relative to root for display.
  List<String> get _breadcrumbs {
    if (_rootDir == null || _currentDir == null) return [];
    if (_currentDir == _rootDir) return [];
    final rel = p.relative(_currentDir!, from: _rootDir!);
    return p.split(rel);
  }

  Future<void> _openFile(String path) async {
    final uri = Uri.file(path);
    if (!await launchUrl(uri)) {
      _showSnack("Couldn't open the file.");
    }
  }

  Future<void> _openInFileManager() async {
    if (_currentDir == null) return;
    final uri = Uri.file(_currentDir!);
    if (!await launchUrl(uri)) {
      _showSnack("Couldn't open the folder.");
    }
  }

  Future<void> _delete(FileSystemEntity entity) async {
    final name = p.basename(entity.path);
    final isDir = entity is Directory;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isDir ? 'Delete folder?' : 'Delete file?'),
        content: Text(
          isDir
              ? 'Delete "$name" and everything inside it? This cannot be undone.'
              : 'Are you sure you want to delete "$name"?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        if (isDir) {
          await (entity as Directory).delete(recursive: true);
        } else {
          await entity.delete();
        }
        _loadFiles();
      } catch (e) {
        _showSnack('Could not delete: $e');
      }
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header ────────────────────────────────────────────────────
              Row(
                children: [
                  if (!_isAtRoot)
                    IconButton(
                      onPressed: _goUp,
                      icon: const Icon(Icons.arrow_back),
                      tooltip: 'Up',
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'My Files',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Browse your downloaded files.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => _loadFiles(),
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Refresh',
                  ),
                  if (_currentDir != null)
                    IconButton(
                      onPressed: _openInFileManager,
                      icon: const Icon(Icons.folder_open),
                      tooltip: 'Open in file manager',
                    ),
                ],
              ),

              // ── Breadcrumb ────────────────────────────────────────────────
              if (_rootDir != null) ...[
                const SizedBox(height: 4),
                _Breadcrumb(
                  rootDir: _rootDir!,
                  breadcrumbs: _breadcrumbs,
                  onTapRoot: () => _loadFiles(dir: _rootDir),
                  onTapSegment: (index) {
                    // Build the path up to that segment.
                    final segments = _breadcrumbs.sublist(0, index + 1);
                    final path = p.joinAll([_rootDir!, ...segments]);
                    _loadFiles(dir: path);
                  },
                ),
              ],
              const SizedBox(height: 16),

              // ── Body ──────────────────────────────────────────────────────
              if (_loading)
                const Center(child: CircularProgressIndicator()),

              if (_error != null)
                Card(
                  color: scheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      _error!,
                      style: TextStyle(color: scheme.onErrorContainer),
                    ),
                  ),
                ),

              if (!_loading && _error == null && (_entities?.isEmpty ?? true))
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      children: [
                        Icon(Icons.folder_off_outlined,
                            size: 48, color: scheme.onSurfaceVariant),
                        const SizedBox(height: 12),
                        Text(
                          _isAtRoot ? 'No files yet' : 'Empty folder',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _isAtRoot
                              ? 'Downloaded files will appear here.'
                              : 'This folder contains no files.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              if (_entities != null)
                for (final entity in _entities!)
                  _EntityRow(
                    entity: entity,
                    onTap: entity is Directory
                        ? () => _enterFolder(entity.path)
                        : () => _openFile(entity.path),
                    onDelete: () => _delete(entity),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Breadcrumb bar ────────────────────────────────────────────────────────────

class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({
    required this.rootDir,
    required this.breadcrumbs,
    required this.onTapRoot,
    required this.onTapSegment,
  });

  final String rootDir;
  final List<String> breadcrumbs;
  final VoidCallback onTapRoot;
  final void Function(int index) onTapSegment;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
      fontFamily: 'monospace',
    );
    final activeStyle = style?.copyWith(color: scheme.primary);

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        GestureDetector(
          onTap: breadcrumbs.isEmpty ? null : onTapRoot,
          child: Text(
            p.basename(rootDir).isEmpty ? rootDir : p.basename(rootDir),
            style: breadcrumbs.isEmpty ? style : activeStyle,
          ),
        ),
        for (int i = 0; i < breadcrumbs.length; i++) ...[
          Text(' / ', style: style),
          GestureDetector(
            onTap: i < breadcrumbs.length - 1 ? () => onTapSegment(i) : null,
            child: Text(
              breadcrumbs[i],
              style: i < breadcrumbs.length - 1 ? activeStyle : style,
            ),
          ),
        ],
      ],
    );
  }
}

// ── Single row ────────────────────────────────────────────────────────────────

class _EntityRow extends StatelessWidget {
  const _EntityRow({
    required this.entity,
    required this.onTap,
    required this.onDelete,
  });

  final FileSystemEntity entity;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDir = entity is Directory;
    final name = p.basename(entity.path);

    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(
                isDir ? Icons.folder_rounded : _iconForFile(entity.path),
                color: isDir ? scheme.tertiary : scheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      isDir ? _dirMeta(entity as Directory) : _fileMeta(entity),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (isDir)
                Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
              IconButton(
                onPressed: onDelete,
                icon: Icon(Icons.delete_outline, color: scheme.error),
                tooltip: isDir ? 'Delete folder' : 'Delete',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

IconData _iconForFile(String path) {
  final ext = p.extension(path).toLowerCase();
  if (['.mp4', '.mkv', '.webm', '.avi', '.mov'].contains(ext)) {
    return Icons.movie_outlined;
  }
  if (['.mp3', '.m4a', '.aac', '.ogg', '.opus', '.flac', '.wav']
      .contains(ext)) {
    return Icons.music_note_outlined;
  }
  if (['.jpg', '.jpeg', '.png', '.gif', '.webp'].contains(ext)) {
    return Icons.image_outlined;
  }
  return Icons.insert_drive_file_outlined;
}

String _fileMeta(FileSystemEntity entity) {
  try {
    final stat = entity.statSync();
    final size = _formatSize(stat.size);
    final date = _formatDate(stat.modified);
    return '$size  ·  $date';
  } catch (_) {
    return '';
  }
}

String _dirMeta(Directory dir) {
  try {
    final stat = dir.statSync();
    final count = dir.listSync().length;
    final date = _formatDate(stat.modified);
    return '$count item${count == 1 ? "" : "s"}  ·  $date';
  } catch (_) {
    return 'Folder';
  }
}

String _formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

String _formatDate(DateTime dt) {
  return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
      '${dt.day.toString().padLeft(2, '0')}' 
      ' ${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';
}
