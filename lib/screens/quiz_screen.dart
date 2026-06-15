import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;

import '../audio/note_player.dart';
import '../theme/app_theme.dart';
import '../midi/midi_service.dart';
import '../quiz/quiz_controller.dart';
import '../quiz/quiz_settings.dart';
import '../widgets/metronome_bar.dart';
import '../widgets/piano_keyboard.dart';
import '../widgets/quiz_settings_sheet.dart';

/// The practice loop: a random prompt, the keyboard, and live feedback.
class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key, required this.mode, required this.midi});

  final QuizMode mode;
  final MidiService midi;

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  QuizController? _controller;
  QuizSettings? _settings;
  MetronomeController? _metronome;
  bool _formulaHint = true;
  bool _dotsHint = true;
  bool _statsBar = true;
  bool _beatIndicator = true;
  bool _noteSound = true;
  final NotePlayer _notes = NotePlayer();

  // Score carried across controller rebuilds (e.g. when the user changes
  // which scales/chords are active). Loaded from storage in [_bootstrap] and
  // persisted on every win, so it survives navigation and app restarts.
  int _carryScore = 0;
  int _carryBestStreak = 0;

  /// True on phones/tablets (used for sizing tweaks).
  bool get _isMobile =>
      !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final settings = await QuizSettings.load();
    final formulaHint = await settings.formulaHintEnabled(widget.mode);
    final dotsHint = await settings.dotsHintEnabled(widget.mode);
    final statsBar = await settings.statsBarEnabled(widget.mode);
    final beatIndicator = await settings.beatIndicatorEnabled(widget.mode);
    final noteSound = await settings.noteSoundEnabled();
    // Restore the persisted session stats before building the controller.
    _carryScore = await settings.quizScore(widget.mode);
    _carryBestStreak = await settings.quizBestStreak(widget.mode);
    // The metronome outlives controller rebuilds; tempo persists globally.
    _metronome = MetronomeController(
      bpm: await settings.metronomeBpm(),
      onBpmChanged: settings.setMetronomeBpm,
    );
    await _rebuildController(settings);
    if (mounted) {
      setState(() {
        _settings = settings;
        _formulaHint = formulaHint;
        _dotsHint = dotsHint;
        _statsBar = statsBar;
        _beatIndicator = beatIndicator;
        _noteSound = noteSound;
      });
    }
  }

  /// (Re)build the controller from the currently-enabled formulas.
  Future<void> _rebuildController(QuizSettings settings) async {
    final old = _controller;
    final QuizController next;
    if (widget.mode == QuizMode.scale) {
      next = QuizController(mode: widget.mode, scales: await settings.enabledScales());
    } else {
      next = QuizController(mode: widget.mode, chords: await settings.enabledChords());
    }
    next
      ..score = _carryScore
      ..bestStreak = _carryBestStreak
      // Covers taps AND MIDI — both route through pressKey.
      ..onAnyPress = (note) {
        if (_noteSound) _notes.play(note);
        if (_beatIndicator) _metronome?.registerHit();
      }
      // Fires on every win: celebrate, then persist the stats so they
      // survive navigation and restarts.
      ..onStatsChanged = () {
        // Stronger buzz when a new best streak is set.
        if (next.bestStreak > _carryBestStreak) {
          HapticFeedback.heavyImpact();
        } else {
          HapticFeedback.mediumImpact();
        }
        _carryScore = next.score;
        _carryBestStreak = next.bestStreak;
        settings.setQuizStats(widget.mode, next.score, next.bestStreak);
      };
    next.bindMidi(widget.midi);
    if (!mounted) {
      next.dispose();
      return;
    }
    setState(() => _controller = next);
    old?.dispose();
  }

  Future<void> _openSettings() async {
    final settings = _settings;
    if (settings == null) return;
    await QuizSettingsSheet.show(
      context,
      mode: widget.mode,
      settings: settings,
      onChanged: (_) {
        // Preserve the running score, then rebuild with the new selection.
        _carryScore = _controller?.score ?? 0;
        _carryBestStreak = _controller?.bestStreak ?? 0;
        _rebuildController(settings);
      },
      onFormulaHintChanged: (on) => setState(() => _formulaHint = on),
      onDotsHintChanged: (on) => setState(() => _dotsHint = on),
      onStatsBarChanged: (on) => setState(() => _statsBar = on),
      onBeatIndicatorChanged: (on) => setState(() => _beatIndicator = on),
      onNoteSoundChanged: (on) => setState(() => _noteSound = on),
      onResetStats: _resetStats,
    );
  }

  /// Zero the persisted score/best streak and the running controller's stats.
  void _resetStats() {
    _carryScore = 0;
    _carryBestStreak = 0;
    _controller?.resetStats();
    _settings?.setQuizStats(widget.mode, 0, 0);
  }

  @override
  void dispose() {
    _controller?.dispose();
    _metronome?.dispose();
    _notes.dispose();
    super.dispose();
  }

  String get _modeLabel =>
      widget.mode == QuizMode.scale ? 'Scales' : 'Chords';

  String get _instruction => widget.mode == QuizMode.scale
      ? 'Play the scale, low to high'
      : 'Play all the chord notes together';

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    // No AppBar: a transparent AppBar still reserves kToolbarHeight at the top
    // of the body, which on short landscape phones overlaps the prompt and
    // leaves no room for the stats bar. Instead we float a thin icon row over
    // the body with a Stack so it costs zero layout height.
    return Scaffold(
      body: controller == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                AnimatedBuilder(
                  animation: controller,
                  builder: (context, _) {
                    // Size the keyboard relative to the available height so the
                    // score bar and prompt always have room above it — critical
                    // in short landscape viewports where a fixed keyboard
                    // overflowed the bottom.
                    final bodyHeight = MediaQuery.of(context).size.height;
                    // Compact mode: landscape PHONES only. Portrait phones and
                    // tablets are tall enough for the regular layout.
                    final compact = _isMobile && bodyHeight < 500;
                    final keyboardHeight = compact
                        ? (bodyHeight * 0.40).clamp(120.0, 240.0)
                        : (bodyHeight * 0.46).clamp(140.0, 240.0);
                    return SafeArea(
                      bottom: false,
                      child: Column(
                        children: [
                          // Reserve room for the floating top bar so the score
                          // bar / prompt start below the icons.
                          const SizedBox(height: _topBarHeight),
                          if (_statsBar) _buildScoreBar(controller, compact),
                          Expanded(
                              child: _buildPrompt(context, controller, compact)),
                          _buildKeyboard(controller, keyboardHeight),
                        ],
                      ),
                    );
                  },
                ),
                _buildTopBar(context),
              ],
            ),
    );
  }

  static const double _topBarHeight = 44;

  /// A thin back / status / settings row floated over the body.
  Widget _buildTopBar(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: _topBarHeight,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              color: AppColors.textPrimary,
              tooltip: 'Back',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            const Spacer(),
            if (_metronome != null) MetronomeBar(controller: _metronome!),
            const Spacer(),
            Icon(
              widget.midi.isConnected ? Icons.piano : Icons.touch_app,
              color: widget.midi.isConnected
                  ? AppColors.correct
                  : AppColors.textSecondary,
              size: 20,
            ),
            IconButton(
              icon: const Icon(Icons.settings),
              color: AppColors.textPrimary,
              tooltip: 'Choose ${_modeLabel.toLowerCase()} to practice',
              onPressed: _openSettings,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScoreBar(QuizController c, bool compact) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Row(
        children: [
          _stat('Score', '${c.score}', AppColors.accent, compact),
          const SizedBox(width: 12),
          _stat('Streak', '${c.streak}', AppColors.accent2, compact),
          const SizedBox(width: 12),
          _stat('Best', '${c.bestStreak}', AppColors.target, compact),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Color color, bool compact) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(vertical: compact ? 5 : 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            // Shrink to fit narrow cards (portrait phones) instead of clipping.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(value,
                  style: TextStyle(
                      fontSize: compact ? 17 : 22,
                      fontWeight: FontWeight.bold,
                      color: color)),
            ),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(label,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.textSecondary)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrompt(BuildContext context, QuizController c, bool compact) {
    final complete = c.roundComplete;
    // Fill the slot between the top bar and the keyboard and center the prompt
    // within it. LayoutBuilder + minHeight = available height makes the column
    // center when there's room and scroll (not overflow) when the viewport is
    // too short. Compact (landscape-phone) mode tightens fonts and gaps so the
    // whole stack fits without scrolling.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: EdgeInsets.symmetric(
            horizontal: 20, vertical: compact ? 4 : 8),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
            Text(
              _instruction,
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: compact ? 13 : 14),
            ),
            SizedBox(height: compact ? 6 : 16),
            AnimatedScale(
              scale: complete ? 1.08 : 1.0,
              duration: const Duration(milliseconds: 250),
              // Scale the name (+ check) down to fit narrow screens instead of
              // overflowing the right edge.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ShaderMask(
                      shaderCallback: (bounds) =>
                          AppColors.accentGradient.createShader(bounds),
                      child: Text(
                        c.promptLabel,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: compact ? 28 : (_isMobile ? 36 : 40),
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          height: 1.1,
                        ),
                      ),
                    ),
                    // Green check pops in beside the name on a correct answer.
                    AnimatedScale(
                      scale: complete ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.elasticOut,
                      child: AnimatedOpacity(
                        opacity: complete ? 1 : 0,
                        duration: const Duration(milliseconds: 150),
                        child: Padding(
                          padding: const EdgeInsets.only(left: 10),
                          child: Icon(Icons.check_circle,
                              color: AppColors.correct,
                              size: compact ? 28 : 36),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_formulaHint) ...[
              SizedBox(height: compact ? 6 : 10),
              // Each degree lights up teal as its note is played correctly;
              // a wrong note clears the lot (in sync with the keyboard).
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < c.formulaDegrees.length; i++) ...[
                      if (i > 0)
                        Text(
                          '-',
                          style: TextStyle(
                            fontSize: compact ? 15 : 18,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textMuted,
                            letterSpacing: 1.5,
                          ),
                        ),
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 150),
                        style: TextStyle(
                          fontSize: compact ? 15 : 18,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.5,
                          color: c.isDegreeSolved(i)
                              ? AppColors.accent
                              : AppColors.textSecondary,
                        ),
                        child: Text(c.formulaDegrees[i]),
                      ),
                    ],
                  ],
                ),
              ),
            ],
            SizedBox(height: compact ? 8 : 16),
            AnimatedOpacity(
              opacity: complete ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: Text(
                'Correct! Press any key to continue',
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: AppColors.correct,
                    fontSize: compact ? 14 : 16,
                    fontWeight: FontWeight.w600),
              ),
            ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKeyboard(QuizController c, double height) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: SizedBox(
          height: height,
          child: PianoKeyboard(
            lowMidi: QuizController.keyboardLowMidi,
            octaves: QuizController.keyboardOctaves,
            feedbackFor: c.feedbackFor,
            isTargetHint: _dotsHint ? c.isTargetHint : (_) => false,
            onKeyDown: c.pressKey,
            onKeyUp: c.releaseKey,
          ),
        ),
      ),
    );
  }
}
