import 'package:flutter/material.dart';

import '../social/social_models.dart';
import '../theme/app_theme.dart';

/// Emoji-on-color circle avatar derived from a profile's avatar seed.
class SocialAvatar extends StatelessWidget {
  const SocialAvatar({super.key, required this.seed, this.radius = 20});

  final String seed;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final (emoji, color) = avatarFromSeed(seed);
    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      alignment: Alignment.center,
      // height: 1.0 strips the emoji's default line-box padding, which is
      // what pushes the glyph off-center inside the circle.
      child: Text(
        emoji,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: radius, height: 1.0),
      ),
    );
  }
}

/// "just now", "5m", "3h", "2d", "Jun 12" — compact feed timestamps.
String relativeTime(DateTime when, [DateTime? now]) {
  final n = now ?? DateTime.now();
  final d = n.difference(when);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes}m';
  if (d.inDays < 1) return '${d.inHours}h';
  if (d.inDays < 7) return '${d.inDays}d';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[when.month - 1]} ${when.day}';
}

/// Card container matching the stats screen's convention.
class SocialCard extends StatelessWidget {
  const SocialCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: padding ?? const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: child,
      );
}

/// Uppercase section header matching stats/settings screens.
class SocialSectionHeader extends StatelessWidget {
  const SocialSectionHeader(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          label.toUpperCase(),
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
      );
}
