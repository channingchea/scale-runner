import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// First-run welcome: a short, friendly explanation of how the app works.
/// Shown once on first launch and re-openable from the home screen's help icon.
class WelcomeSheet extends StatelessWidget {
  const WelcomeSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const WelcomeSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
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
                shaderCallback: (b) =>
                    AppColors.accentGradient.createShader(b),
                child: const Text(
                  'Welcome to Scale Runner',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'A few seconds of how it works:',
                style:
                    TextStyle(color: AppColors.textSecondary, fontSize: 14),
              ),
              const SizedBox(height: 20),
              _row(
                Icons.school,
                'Pick a practice mode',
                'Scales and Chords quiz you with random prompts. '
                    'Scale Running is a continuous drill in time with the '
                    'metronome.',
              ),
              _row(
                Icons.visibility,
                'Read the prompt',
                'You\'ll see a name like "G Major" and its formula, e.g. '
                    '1-2-3-4-5-6-7. Each number is a scale degree — they '
                    'light up as you play the right notes.',
              ),
              _row(
                Icons.touch_app,
                'No piano needed',
                'Tap the on-screen keys to answer. Correct notes turn '
                    'green; wrong ones flash red and you just try again.',
              ),
              _row(
                Icons.piano,
                'Got a MIDI keyboard?',
                'Tap the banner on the home screen to connect over USB or '
                    'Bluetooth and play on the real thing.',
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text("Let's play"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(IconData icon, String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Icon(icon, color: AppColors.accent, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
