import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// What the user chose to do next from the summary.
enum VoicingSummaryAction { done, again, pickAnother }

/// End-of-session summary for a Voicings drill.
///
/// Deliberately thin compared with every other mode's summary: the voicing's
/// name, how many keys you landed, and how long you practised. **No accuracy,
/// no tier, no share.** There is nothing to score here and pretending
/// otherwise would undercut the whole mode.
class VoicingSessionSummarySheet extends StatelessWidget {
  const VoicingSessionSummarySheet({
    super.key,
    required this.voicingName,
    required this.formula,
    required this.keysCompleted,
    required this.keyCount,
    required this.elapsed,
  });

  final String voicingName;
  final String formula;
  final int keysCompleted;
  final int keyCount;
  final Duration elapsed;

  bool get _finished => keysCompleted >= keyCount;

  static Future<VoicingSummaryAction> show(
    BuildContext context, {
    required String voicingName,
    required String formula,
    required int keysCompleted,
    required int keyCount,
    required Duration elapsed,
  }) async {
    final action = await showModalBottomSheet<VoicingSummaryAction>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => VoicingSessionSummarySheet(
        voicingName: voicingName,
        formula: formula,
        keysCompleted: keysCompleted,
        keyCount: keyCount,
        elapsed: elapsed,
      ),
    );
    return action ?? VoicingSummaryAction.done;
  }

  static String _fmt(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

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
            Text(
              _finished ? 'All keys' : 'Session ended',
              textAlign: TextAlign.center,
              style: const TextStyle(
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
                voicingName,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1.15,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              formula,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.accent,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                _statBox('Keys', '$keysCompleted of $keyCount',
                    AppColors.accent2),
                const SizedBox(width: 10),
                _statBox('Practised', _fmt(elapsed), AppColors.target),
              ],
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => Navigator.of(context)
                  .pop(VoicingSummaryAction.again),
              icon: const Icon(Icons.refresh),
              label: const Text('Run it again'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => Navigator.of(context)
                  .pop(VoicingSummaryAction.pickAnother),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.border),
              ),
              child: const Text('Pick another voicing'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statBox(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceHigh,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: color,
                  fontFeatures: tabularFigures,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
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
