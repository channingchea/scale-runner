import 'package:flutter/material.dart';

import '../onboarding/mode_guides.dart';
import '../quiz/quiz_settings.dart';
import '../theme/app_theme.dart';
import '../theory/fretboard.dart';
import '../ui/responsive.dart';
import 'fretboard_view.dart' show FretboardLabels, TwinDotMode;
import 'guide_demo.dart';

/// Shows [mode]'s guide the first time it is entered on this device, and
/// marks it seen. Call from a screen's post-frame callback. Returns after the
/// sheet is dismissed, or at once when there was nothing to show.
Future<void> maybeShowGuide(BuildContext context, GuideMode mode) async {
  final settings = await QuizSettings.load();
  if (await settings.guideSeen(mode)) return;
  await settings.setGuideSeen(mode);
  if (!context.mounted) return;
  await ModeGuideSheet.show(context, mode);
}

/// A mode's how-to: title, a looping demo on the player's instrument, and a
/// few numbered lines. Styled like [WelcomeSheet]; re-openable from every
/// mode's "?" button.
class ModeGuideSheet extends StatelessWidget {
  const ModeGuideSheet({
    super.key,
    required this.mode,
    required this.instrument,
    this.leftHanded = false,
    this.twinMode = TwinDotMode.primaryAndGhost,
    this.labels = const FretboardLabels(),
  });

  final GuideMode mode;
  final Instrument instrument;
  final bool leftHanded;
  final TwinDotMode twinMode;
  final FretboardLabels labels;

  /// Loads the instrument settings so the demo matches what the player
  /// actually practises on, then presents the sheet.
  static Future<void> show(BuildContext context, GuideMode mode) async {
    final settings = await QuizSettings.load();
    final instrument = await settings.instrument();
    final leftHanded = await settings.leftHanded();
    final twinMode = await settings.guitarTwinMode();
    final labels = await settings.fretboardLabels();
    if (!context.mounted) return;
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => ModeGuideSheet(
        mode: mode,
        instrument: instrument,
        leftHanded: leftHanded,
        twinMode: twinMode,
        labels: labels,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final guide = modeGuides[mode]!;
    final size = MediaQuery.sizeOf(context);
    final tall = isDesktopPlatform || size.shortestSide >= 600;
    // The fretboard's vertical box needs more room than a keyboard strip.
    final demoHeight = instrument == Instrument.guitar
        ? (tall ? 220.0 : 170.0)
        : (tall ? 160.0 : 120.0);
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: size.height * 0.85),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              ShaderMask(
                shaderCallback: (b) => AppColors.accentGradient.createShader(b),
                child: Text(
                  guide.title,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'How it works:',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
              ),
              const SizedBox(height: 16),
              GuideDemo(
                frames: guide.demo,
                instrument: instrument,
                leftHanded: leftHanded,
                twinMode: twinMode,
                labels: labels,
                height: demoHeight,
              ),
              const SizedBox(height: 18),
              for (var i = 0; i < guide.lines.length; i++)
                _line(i + 1, guide.lines[i]),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Got it'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _line(int n, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              '$n',
              style: const TextStyle(
                color: AppColors.accent,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                text,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  height: 1.35,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
