import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../runner/jam_mode_controller.dart';

/// Plain snapshot of a finished Jam Mode session, captured the moment the drill
/// stops so the summary survives even after the controller is reset.
class JamSessionStats {
  const JamSessionStats({
    required this.barsJudged,
    required this.accuracy,
    required this.onTimeRate,
    required this.bestStreak,
    required this.tier,
    required this.weakestQuality,
    required this.weakestDegree,
  });

  final int barsJudged;
  final double accuracy;
  final double onTimeRate;
  final int bestStreak;
  final JamTier tier;
  final String? weakestQuality;
  final String? weakestDegree;

  /// Capture the current state of [c] before it gets reset.
  factory JamSessionStats.from(JamModeController c) => JamSessionStats(
        barsJudged: c.barsJudged,
        accuracy: c.accuracy,
        onTimeRate: c.onTimeRate,
        bestStreak: c.bestStreak,
        tier: c.tier,
        weakestQuality: c.weakestQuality?.key,
        weakestDegree: c.weakestDegree?.key,
      );
}

/// End-of-session summary: overall accuracy, on-time %, best streak, the
/// weakest chord quality and degree, and the performance tier.
class JamSessionSummarySheet extends StatelessWidget {
  const JamSessionSummarySheet({super.key, required this.stats});

  final JamSessionStats stats;

  static Future<void> show(BuildContext context, JamSessionStats stats) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => JamSessionSummarySheet(stats: stats),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _grabber(),
            const SizedBox(height: 8),
            const Text(
              'Session complete',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 6),
            ShaderMask(
              shaderCallback: (b) => AppColors.accentGradient.createShader(b),
              child: Text(
                stats.tier.label,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1.1,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                _statBox('Accuracy', '${(stats.accuracy * 100).round()}%',
                    AppColors.correct),
                const SizedBox(width: 10),
                _statBox('On time', '${(stats.onTimeRate * 100).round()}%',
                    AppColors.accent2),
                const SizedBox(width: 10),
                _statBox('Bars', '${stats.barsJudged}', AppColors.target),
              ],
            ),
            const SizedBox(height: 10),
            _statBox('Best streak', '${stats.bestStreak}', AppColors.accent,
                wide: true),
            const SizedBox(height: 18),
            if (stats.barsJudged > 0) ...[
              const Text(
                'WORK ON',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),
              _weakRow('Weakest quality', stats.weakestQuality),
              const SizedBox(height: 6),
              _weakRow('Weakest degree', stats.weakestDegree),
              const SizedBox(height: 18),
            ],
            FilledButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statBox(String label, String value, Color color, {bool wide = false}) {
    final box = Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Text(value,
              style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: color,
                  fontFeatures: tabularFigures)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecondary)),
        ],
      ),
    );
    return wide ? box : Expanded(child: box);
  }

  Widget _weakRow(String label, String? value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 13)),
        Text(
          value ?? '—',
          style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _grabber() => Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.border,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
}
