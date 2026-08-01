import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../runner/scale_run_controller.dart';

/// Plain snapshot of a finished Scale Running session, captured the moment the
/// drill stops so the summary survives even after the controller is reset.
class RunSessionStats {
  const RunSessionStats({
    required this.keysCompleted,
    required this.accuracy,
    required this.onTimeRate,
    required this.bestStreak,
    required this.tier,
    required this.weakestKey,
    required this.weakestMode,
  });

  final int keysCompleted;
  final double accuracy;
  final double onTimeRate;
  final int bestStreak;
  final RunTier tier;
  final String? weakestKey;
  final String? weakestMode;

  /// Capture the current state of [c] before it gets reset.
  factory RunSessionStats.from(ScaleRunController c) => RunSessionStats(
        keysCompleted: c.keysCompleted,
        accuracy: c.accuracy,
        onTimeRate: c.onTimeRate,
        bestStreak: c.bestStreak,
        tier: c.tier,
        weakestKey: c.weakestKey?.key,
        weakestMode: c.weakestMode?.key,
      );

  /// Whether anything was actually judged (used to gate the "WORK ON" section
  /// and the merge into lifetime stats).
  bool get hasData => keysCompleted > 0 || accuracy > 0 || weakestKey != null;
}

/// End-of-session summary: overall accuracy, on-time %, keys completed, best
/// streak, the weakest key and mode, and the performance tier.
class ScaleRunSessionSummarySheet extends StatelessWidget {
  const ScaleRunSessionSummarySheet({super.key, required this.stats});

  final RunSessionStats stats;

  static Future<void> show(BuildContext context, RunSessionStats stats) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => ScaleRunSessionSummarySheet(stats: stats),
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
                _statBox('Keys', '${stats.keysCompleted}', AppColors.target),
              ],
            ),
            const SizedBox(height: 10),
            _statBox('Best streak', '${stats.bestStreak}', AppColors.accent,
                wide: true),
            const SizedBox(height: 18),
            if (stats.hasData) ...[
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
              _weakRow('Weakest key', stats.weakestKey),
              const SizedBox(height: 6),
              _weakRow('Weakest mode', stats.weakestMode),
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
