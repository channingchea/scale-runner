import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../purchases/paywall_sheet.dart';
import '../theme/app_theme.dart';

/// False while the app is beta-only. Flip to true on the day both store
/// listings are public — that is the whole launch change for share links.
///
/// It matters because the store URLs 404 until then, so every shared link
/// lands a new user on a dead page.
const bool kPubliclyLaunched = true;

/// Where "share with friends" points: the public store listing once launched,
/// the beta invite before that. Keep in sync with the "Get Scale Runner"
/// button in web_hosting/hostinger/invite/index.html.
String get appShareUrl => (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS)
    ? (kPubliclyLaunched
        ? 'https://apps.apple.com/app/id6795850810'
        : 'https://testflight.apple.com/join/vMhnCACs')
    : (kPubliclyLaunched
        ? 'https://play.google.com/store/apps/details?id=com.scalerunner.app'
        : 'https://appdistribution.firebase.google.com/i/a3847e100f0ac630');

/// Celebrates hitting a streak milestone (3, 7, 14, 30, 100 days) and lets
/// the user share their progress — each share is a friend-referral for free.
class StreakMilestoneSheet extends StatelessWidget {
  const StreakMilestoneSheet({super.key, required this.streak});

  final int streak;

  static Future<void> show(BuildContext context, int streak) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => StreakMilestoneSheet(streak: streak),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      icon: Icons.local_fire_department,
      iconGradient: true,
      title: '$streak-day streak!',
      body: streak >= 30
          ? 'That\'s serious dedication — $streak days of practice in a row.'
          : 'You\'ve practiced $streak days in a row. Keep it rolling!',
      primary: FilledButton.icon(
        icon: const Icon(Icons.ios_share, size: 18),
        label: const Text('Share your streak'),
        onPressed: () {
          SharePlus.instance.share(ShareParams(
            text: '🔥 I\'ve practiced piano $streak days in a row with '
                'Scale Runner! Join me: $appShareUrl',
          ));
        },
      ),
      secondaryLabel: 'Keep practicing',
    );
  }
}

/// Shown on app open when the Pro weekly freeze auto-repaired a missed day.
class StreakFrozenSheet extends StatelessWidget {
  const StreakFrozenSheet({super.key, required this.streak});

  final int streak;

  static Future<void> show(BuildContext context, int streak) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => StreakFrozenSheet(streak: streak),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      icon: Icons.ac_unit,
      title: 'Streak saved',
      body: 'You missed a day, but your Pro streak freeze kept your '
          '$streak-day streak alive. You get one freeze per week — '
          'practice today to stay safe.',
      secondaryLabel: 'Nice',
    );
  }
}

/// Shown on app open when a free user's streak broke: the conversion moment.
class StreakLostSheet extends StatelessWidget {
  const StreakLostSheet({super.key, required this.lostStreak});

  final int lostStreak;

  static Future<void> show(BuildContext context, int lostStreak) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => StreakLostSheet(lostStreak: lostStreak),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _SheetScaffold(
      icon: Icons.whatshot,
      iconMuted: true,
      title: 'Your $lostStreak-day streak ended',
      body: 'Life happens. Pro members get a weekly streak freeze that '
          'would have saved it — and every practice mode, forever.',
      primary: FilledButton(
        onPressed: () async {
          final navigator = Navigator.of(context);
          await PaywallSheet.show(context);
          if (navigator.mounted) navigator.pop();
        },
        child: const Text('Protect my next streak'),
      ),
      secondaryLabel: 'Start again',
    );
  }
}

/// Shared layout: drag handle, big icon, title, body, optional primary
/// button, and a dismiss text button.
class _SheetScaffold extends StatelessWidget {
  const _SheetScaffold({
    required this.icon,
    required this.title,
    required this.body,
    required this.secondaryLabel,
    this.primary,
    this.iconGradient = false,
    this.iconMuted = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final String secondaryLabel;
  final Widget? primary;
  final bool iconGradient;
  final bool iconMuted;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 22),
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                gradient: iconGradient ? AppColors.accentGradient : null,
                color: iconGradient ? null : AppColors.surfaceHigh,
                shape: BoxShape.circle,
                border: iconGradient
                    ? null
                    : Border.all(color: AppColors.border),
              ),
              child: Icon(
                icon,
                size: 38,
                color: iconGradient
                    ? const Color(0xFF06251F)
                    : (iconMuted ? AppColors.textMuted : AppColors.accent),
              ),
            ),
            const SizedBox(height: 18),
            ShaderMask(
              shaderCallback: (b) => AppColors.accentGradient.createShader(b),
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            if (primary != null) ...[
              SizedBox(width: double.infinity, child: primary),
              const SizedBox(height: 8),
            ],
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(secondaryLabel),
            ),
          ],
        ),
      ),
    );
  }
}
