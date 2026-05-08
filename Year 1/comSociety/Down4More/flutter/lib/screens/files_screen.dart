import 'package:flutter/material.dart';

import '../widgets/empty_placeholder.dart';

class FilesScreen extends StatelessWidget {
  const FilesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmptyPlaceholder(
      icon: Icons.folder_open,
      title: 'My Files',
      message:
          'Browse what you have already downloaded, with quick actions: open,'
          ' reveal in file manager, delete, re-download.',
      roadmapChip: 'Coming in PR 5',
    );
  }
}
