import 'package:flutter/foundation.dart';

import '../models/playlist_entry.dart';
import '../services/ytdlp_service.dart';

/// Phases the playlist screen can be in.
enum PlaylistPhase {
  idle,
  fetching,
  ready,
  error,
}

/// Manages fetching a playlist's entries and tracking selection state.
///
/// Once the user has selected entries, the Playlist screen hands them off
/// to a [DownloadQueueController] to actually download.
class PlaylistController extends ChangeNotifier {
  PlaylistController({YtDlpService? service})
      : _service = service ?? YtDlpService();

  final YtDlpService _service;

  PlaylistPhase _phase = PlaylistPhase.idle;
  List<PlaylistEntry> _entries = [];
  final Set<int> _selected = {};
  String? _errorMessage;

  PlaylistPhase get phase => _phase;
  List<PlaylistEntry> get entries => List.unmodifiable(_entries);
  Set<int> get selectedIndices => Set.unmodifiable(_selected);
  String? get errorMessage => _errorMessage;
  int get selectedCount => _selected.length;

  bool isSelected(int index) => _selected.contains(index);

  void toggleSelection(int index) {
    if (_selected.contains(index)) {
      _selected.remove(index);
    } else {
      _selected.add(index);
    }
    notifyListeners();
  }

  void selectAll() {
    _selected.clear();
    for (int i = 0; i < _entries.length; i++) {
      _selected.add(i);
    }
    notifyListeners();
  }

  void deselectAll() {
    _selected.clear();
    notifyListeners();
  }

  /// Fetch all entries in the playlist URL.
  Future<void> fetchPlaylist(String url) async {
    _phase = PlaylistPhase.fetching;
    _entries = [];
    _selected.clear();
    _errorMessage = null;
    notifyListeners();

    try {
      _entries = await _service.fetchPlaylist(url.trim());
      if (_entries.isEmpty) {
        _phase = PlaylistPhase.error;
        _errorMessage = 'No videos found in this playlist.';
      } else {
        _phase = PlaylistPhase.ready;
        selectAll();
      }
    } on YtDlpException catch (e) {
      _phase = PlaylistPhase.error;
      _errorMessage = e.message;
    } catch (e) {
      _phase = PlaylistPhase.error;
      _errorMessage = 'Unexpected error: $e';
    }
    notifyListeners();
  }

  /// Get the selected entries as records suitable for the queue controller.
  List<({String url, String title, String? thumbnailUrl})> get selectedEntries {
    return _selected
        .where((i) => i < _entries.length)
        .map((i) => (
              url: _entries[i].url,
              title: _entries[i].title,
              thumbnailUrl: _entries[i].thumbnailUrl,
            ))
        .toList();
  }

  void reset() {
    _phase = PlaylistPhase.idle;
    _entries = [];
    _selected.clear();
    _errorMessage = null;
    notifyListeners();
  }
}
