import 'package:flutter/material.dart';

import '../widgets/empty_placeholder.dart';

class BatchScreen extends StatelessWidget {
  const BatchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmptyPlaceholder(
      icon: Icons.dynamic_feed,
      title: 'Batch',
      message:
          'Paste a list of URLs (one per line) and download them all with the'
          ' same settings. Concurrency limit comes from your Settings.',
      roadmapChip: 'Coming in PR 4',
    );
  }
}
