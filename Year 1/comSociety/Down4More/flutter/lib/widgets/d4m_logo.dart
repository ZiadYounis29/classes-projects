import 'package:flutter/material.dart';

/// The Down4More wordmark: a rounded primary-colored tile with a play triangle,
/// followed by "Down" + accent "4More". Auto-adapts to the current theme — on
/// the Crimson preset it renders as the classic black/red brand; on Sky as
/// blue-on-white; etc.
class D4MLogo extends StatelessWidget {
  const D4MLogo({
    super.key,
    this.showText = true,
    this.size = 28,
  });

  /// Whether to show the wordmark to the right of the icon tile. Disable when
  /// the nav rail is collapsed.
  final bool showText;

  /// Approximate height of the rendered text. The icon tile is sized
  /// proportionally.
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size * 1.25,
          height: size * 1.25,
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(size * 0.28),
          ),
          child: Icon(
            Icons.play_arrow_rounded,
            color: scheme.onPrimary,
            size: size * 0.95,
          ),
        ),
        if (showText) ...[
          SizedBox(width: size * 0.4),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'Down',
                  style: TextStyle(
                    fontSize: size,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: scheme.onSurface,
                  ),
                ),
                TextSpan(
                  text: '4More',
                  style: TextStyle(
                    fontSize: size,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
