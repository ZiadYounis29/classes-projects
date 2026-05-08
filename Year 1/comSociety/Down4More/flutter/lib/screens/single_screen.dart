import 'package:flutter/material.dart';

import '../widgets/empty_placeholder.dart';

class SingleScreen extends StatelessWidget {
  const SingleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const EmptyPlaceholder(
      icon: Icons.link,
      title: 'Single download',
      message:
          'Paste a URL, pick a quality, hit download. Lands in PR 3 — this PR'
          ' is just the scaffold so you can see the shell, navigate the tabs,'
          ' and try out themes.',
      roadmapChip: 'Coming in PR 3',
    );
  }
}
