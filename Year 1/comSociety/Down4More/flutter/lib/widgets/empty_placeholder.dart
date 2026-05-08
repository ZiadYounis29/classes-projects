import 'package:flutter/material.dart';

/// Shown on each tab whose feature hasn't shipped yet. PR 2 is the scaffold,
/// so most tabs render this with the relevant icon and a roadmap chip.
class EmptyPlaceholder extends StatelessWidget {
  const EmptyPlaceholder({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.roadmapChip,
  });

  final IconData icon;
  final String title;
  final String message;

  /// Optional chip that names which PR will deliver this feature. e.g.
  /// `"Coming in PR 3"`.
  final String? roadmapChip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 48,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
              if (roadmapChip != null) ...[
                const SizedBox(height: 20),
                Chip(
                  visualDensity: VisualDensity.compact,
                  side: BorderSide(color: scheme.outlineVariant),
                  backgroundColor: scheme.surfaceContainerHighest,
                  label: Text(
                    roadmapChip!,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
