import 'package:flutter/material.dart';

import '../widgets/empty_placeholder.dart';

class PlaylistScreen extends StatelessWidget {
  const PlaylistScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmptyPlaceholder(
      icon: Icons.list_alt,
      title: 'Playlist',
      message:
          'Paste a playlist URL, pick which videos you want, queue them all up'
          ' at once.',
      roadmapChip: 'Coming in PR 4',
    );
  }
}
