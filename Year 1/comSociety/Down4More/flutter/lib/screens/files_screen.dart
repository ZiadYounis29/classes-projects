import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../settings/app_settings.dart';

/// Downloaded-files browser.
///
/// Lists all files in the configured download directory with quick actions:
/// open, reveal in file manager, delete, and re-download (future).
class FilesScreen extends StatefulWidget {
  const FilesScreen({super.key, required this.appSettings});
  final AppSettings appSettings;

  @override
  State<FilesScreen> createState() => _FilesScreenState();
}

class _FilesScreenState extends State<FilesScreen> {
  List<FileSystemEntity>? _files;
  String? _dir;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final dir = await _resolveDir();
      _dir = dir;
      final d = Directory(dir);
      if (!await d.exists()) {
        await d.create(recursive: true);
      }

      final entities = await d.list().toList();
      entities.sort((a, b) {
        final aStat = a.statSync();
        final bStat = b.statSync();
        return bStat.modified.compareTo(aStat.modified);
      });

      setState(() {
        _files = entities;
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

  Future<void> _openFile(String path) async {
    final uri = Uri.file(path);
    if (!await launchUrl(uri)) {
      _showSnack("Couldn't open the file.");
    }
  }

  Future<void> _openFolder() async {
    if (_dir == null) return;
    final uri = Uri.file(_dir!);
    if (!await launchUrl(uri)) {
      _showSnack("Couldn't open the folder.");
    }
  }

  Future<void> _deleteFile(FileSystemEntity entity) async {
    final name = p.basename(entity.path);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete file?'),
        content: Text('Are you sure you want to delete "$name"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await entity.delete();
      _loadFiles();
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
              Row(
                children: [
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
                        const SizedBox(height: 4),
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
                    onPressed: _loadFiles,
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Refresh',
                  ),
                  if (_dir != null)
                    IconButton(
                      onPressed: _openFolder,
                      icon: const Icon(Icons.folder_open),
                      tooltip: 'Open folder',
                    ),
                ],
              ),
              if (_dir != null) ...[
                const SizedBox(height: 4),
                Text(
                  _dir!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
              const SizedBox(height: 16),

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

              if (!_loading && _error == null && (_files?.isEmpty ?? true))
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      children: [
                        Icon(Icons.folder_off_outlined,
                            size: 48, color: scheme.onSurfaceVariant),
                        const SizedBox(height: 12),
                        Text(
                          'No files yet',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Downloaded files will appear here.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              if (_files != null)
                for (final entity in _files!)
                  Card(
                    margin: const EdgeInsets.only(bottom: 4),
                    child: InkWell(
                      onTap: () => _openFile(entity.path),
                      borderRadius: BorderRadius.circular(16),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            Icon(
                              _iconForFile(entity.path),
                              color: scheme.primary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    p.basename(entity.path),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Text(
                                    _fileMeta(entity),
                                    style:
                                        theme.textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => _deleteFile(entity),
                              icon: Icon(Icons.delete_outline,
                                  color: scheme.error),
                              tooltip: 'Delete',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }

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
      '${dt.day.toString().padLeft(2, '0')} '
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}';
}
