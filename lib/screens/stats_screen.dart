import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../quiz/quiz_controller.dart';
import '../quiz/quiz_settings.dart';
import '../social/social_models.dart';
import '../social/social_service.dart';
import '../streak/streak_service.dart';
import '../ui/responsive.dart';
import 'social_screen.dart';

/// Lifetime stats across every mode: Scale Running, Jam, Inversion Running,
/// and the Scale/Chord quizzes. Read-only — data is written by each mode's
/// own session-end hook.
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  bool _loading = true;
  Map<String, (int, int)> _runKeys = {};
  Map<String, (int, int)> _runModes = {};
  Map<String, (int, int)> _jamQualities = {};
  Map<String, (int, int)> _jamDegrees = {};
  Map<String, (int, int)> _invChords = {};
  ModeStats _modeStats = const ModeStats();
  int _scaleScore = 0;
  int _scaleStreak = 0;
  int _chordScore = 0;
  int _chordStreak = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await StreakService.instance.init();
    final settings = await QuizSettings.load();
    final results = await Future.wait([
      settings.runKeyStats(),
      settings.runModeStats(),
      settings.jamQualityStats(),
      settings.jamDegreeStats(),
      settings.invChordStats(),
    ]);
    final modeStats = await settings.modeStats();
    final scaleScore = await settings.quizScore(QuizMode.scale);
    final scaleStreak = await settings.quizBestStreak(QuizMode.scale);
    final chordScore = await settings.quizScore(QuizMode.chord);
    final chordStreak = await settings.quizBestStreak(QuizMode.chord);
    if (!mounted) return;
    setState(() {
      _runKeys = results[0];
      _runModes = results[1];
      _jamQualities = results[2];
      _jamDegrees = results[3];
      _invChords = results[4];
      _modeStats = modeStats;
      _scaleScore = scaleScore;
      _scaleStreak = scaleStreak;
      _chordScore = chordScore;
      _chordStreak = chordStreak;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Stats')),
      body: ContentColumn(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  _sectionHeader('Mode scores'),
                  _scoreCaption(
                      'A 0–100 score per mode, blending accuracy with how much '
                      'you\'ve practiced. Shared with friends.'),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _modeScoreTile(
                          'SCALE RUN', _modeStats.scaleRunningScore),
                      const SizedBox(width: 10),
                      _modeScoreTile('JAM', _modeStats.jamScore),
                      const SizedBox(width: 10),
                      _modeScoreTile('INVERSION', _modeStats.inversionScore),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _sectionHeader('Practice streak'),
                  _card(
                    child: Row(
                      children: [
                        _streakStat(
                            '${StreakService.instance.currentStreak}', 'current'),
                        _streakStat(
                            '${StreakService.instance.bestStreak}', 'best'),
                        _streakStat(
                            '${StreakService.instance.totalPracticeDays}',
                            'total days'),
                      ],
                    ),
                  ),
                  if (!SocialService.instance.isSignedIn) ...[
                    const SizedBox(height: 8),
                    _syncCta(),
                  ],
                  const SizedBox(height: 20),
                  _sectionHeader('Scale Running'),
                  _card(
                    child: Column(
                      children: [
                        _AccuracyBarList(
                          stats: _runKeys,
                          emptyLabel: 'Play a Scale Running session to see '
                              'per-key stats here.',
                        ),
                        const SizedBox(height: 4),
                        _subLabel('By mode'),
                        _AccuracyBarList(
                          stats: _runModes,
                          emptyLabel: 'No mode data yet.',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _sectionHeader('Jam Mode'),
                  _card(
                    child: Column(
                      children: [
                        _subLabel('By quality'),
                        _AccuracyBarList(
                          stats: _jamQualities,
                          emptyLabel: 'Play a Jam Mode session to see '
                              'per-quality stats here.',
                        ),
                        const SizedBox(height: 4),
                        _subLabel('By degree'),
                        _AccuracyBarList(
                          stats: _jamDegrees,
                          emptyLabel: 'No degree data yet.',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _sectionHeader('Inversion Running'),
                  _card(
                    child: _AccuracyBarList(
                      stats: _invChords,
                      emptyLabel: 'Play an Inversion Running session to see '
                          'per-chord stats here.',
                    ),
                  ),
                  const SizedBox(height: 20),
                  _sectionHeader('Quiz'),
                  Row(
                    children: [
                      Expanded(
                        child: _quizModeCard(
                            'Scales', _scaleScore, _scaleStreak),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _quizModeCard(
                            'Chords', _chordScore, _chordStreak),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  Widget _scoreCaption(String text) => Text(
        text,
        style: const TextStyle(
            color: AppColors.textMuted, fontSize: 12, height: 1.35),
      );

  Widget _modeScoreTile(String label, int? score) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              Text(
                score == null ? '—' : '$score',
                style: TextStyle(
                    color:
                        score == null ? AppColors.textMuted : AppColors.accent,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    fontFeatures: tabularFigures),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4),
              ),
            ],
          ),
        ),
      );

  Widget _streakStat(String value, String label) => Expanded(
        child: Column(
          children: [
            Text(value,
                style: const TextStyle(
                    color: AppColors.accent,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    fontFeatures: tabularFigures)),
            Text(label,
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 11)),
          ],
        ),
      );

  Widget _syncCta() => InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SocialScreen()));
          if (mounted) setState(() {});
        },
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
          ),
          child: const Row(
            children: [
              Icon(Icons.cloud_upload_outlined,
                  color: AppColors.accent, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Sign in to back up your streak and practice with friends',
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 13),
                ),
              ),
              Icon(Icons.chevron_right, color: AppColors.textMuted, size: 18),
            ],
          ),
        ),
      );

  Widget _card({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: child,
      );

  Widget _quizModeCard(String title, int score, int streak) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title.toUpperCase(),
                style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6)),
            const SizedBox(height: 10),
            Text('$score',
                style: const TextStyle(
                    color: AppColors.accent,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    fontFeatures: tabularFigures)),
            const Text('score',
                style:
                    TextStyle(color: AppColors.textSecondary, fontSize: 11)),
            const SizedBox(height: 8),
            Text('$streak',
                style: const TextStyle(
                    color: AppColors.target,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    fontFeatures: tabularFigures)),
            const Text('best streak',
                style:
                    TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          ],
        ),
      );

  Widget _sectionHeader(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
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

  Widget _subLabel(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            label,
            style: const TextStyle(
                color: AppColors.textMuted,
                fontSize: 11,
                fontWeight: FontWeight.w600),
          ),
        ),
      );
}

/// A sorted-ascending list of accuracy bars for a `key → (attempts, correct)`
/// stats map. Entries with fewer than 5 attempts still show their accuracy
/// but can't be flagged "weakest". Shows [emptyLabel] when [stats] is empty.
class _AccuracyBarList extends StatelessWidget {
  const _AccuracyBarList({required this.stats, required this.emptyLabel});

  final Map<String, (int, int)> stats;
  final String emptyLabel;

  static const _weakestThreshold = 5;

  @override
  Widget build(BuildContext context) {
    if (stats.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          emptyLabel,
          style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 13,
              fontStyle: FontStyle.italic),
        ),
      );
    }
    final entries = stats.entries.toList()
      ..sort((a, b) => _accuracyOf(a.value).compareTo(_accuracyOf(b.value)));
    String? weakestKey;
    for (final e in entries) {
      if (e.value.$1 >= _weakestThreshold) {
        weakestKey = e.key;
        break;
      }
    }
    return Column(
      children: [
        for (final e in entries)
          _StatBar(
            label: e.key,
            attempts: e.value.$1,
            correct: e.value.$2,
            isWeakest: e.key == weakestKey,
          ),
      ],
    );
  }

  static double _accuracyOf((int, int) v) => v.$1 == 0 ? 0 : v.$2 / v.$1;
}

class _StatBar extends StatelessWidget {
  const _StatBar({
    required this.label,
    required this.attempts,
    required this.correct,
    required this.isWeakest,
  });

  final String label;
  final int attempts;
  final int correct;
  final bool isWeakest;

  double get _accuracy => attempts == 0 ? 0 : correct / attempts;

  @override
  Widget build(BuildContext context) {
    final pct = (_accuracy * 100).round();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // The name+badge group owns all leftover space so the value
              // text sits flush against the row's right edge.
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                            fontSize: 14),
                      ),
                    ),
                    if (isWeakest) ...[
                      const SizedBox(width: 6),
                      _weakestBadge(),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$pct% accuracy · $attempts plays',
                style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                    fontFeatures: tabularFigures),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _accuracy,
              minHeight: 8,
              backgroundColor: AppColors.surfaceHigh,
              color: isWeakest ? AppColors.wrong : AppColors.accent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _weakestBadge() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.wrong.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Text(
          'WEAKEST',
          style: TextStyle(
              color: AppColors.wrong,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4),
        ),
      );
}
