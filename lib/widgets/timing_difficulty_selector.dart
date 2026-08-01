import 'package:flutter/material.dart';

import '../quiz/quiz_settings.dart';
import '../theme/app_theme.dart';

/// Three-way Easy / Normal / Strict picker for the global timing difficulty,
/// shared by every mode's settings sheet. Persists via [settings] and calls
/// [onChanged] so the host screen can rebuild its controller.
class TimingDifficultySelector extends StatelessWidget {
  const TimingDifficultySelector({
    super.key,
    required this.value,
    required this.settings,
    required this.onChanged,
  });

  final TimingDifficulty value;
  final QuizSettings settings;

  /// Called with the newly selected difficulty after it's been persisted.
  final ValueChanged<TimingDifficulty> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: SegmentedButton<TimingDifficulty>(
            segments: [
              for (final d in TimingDifficulty.values)
                ButtonSegment(value: d, label: Text(d.label)),
            ],
            selected: {value},
            onSelectionChanged: (sel) async {
              final d = sel.first;
              await settings.setTimingDifficulty(d);
              onChanged(d);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(
            'How tight the timing windows are, in every mode: '
            'on-beat within ${value.onBeatMs}ms, close within ${value.closeMs}ms.',
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 12),
          ),
        ),
      ],
    );
  }
}
