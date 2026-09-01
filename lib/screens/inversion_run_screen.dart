import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../audio/note_player.dart';
import '../theme/app_theme.dart';
import '../midi/ble_latency.dart';
import '../midi/midi_service.dart';
import '../purchases/paywall_sheet.dart';
import '../quiz/quiz_settings.dart';
import '../runner/inversion_run_controller.dart';
import '../social/social_service.dart';
import '../streak/streak_service.dart';
import '../ui/responsive.dart';
import '../widgets/inversion_run_settings_sheet.dart';
import '../widgets/inversion_session_summary_sheet.dart';
import '../widgets/metronome_bar.dart';
import '../widgets/piano_keyboard.dart';
import '../widgets/reminder_prompt_sheet.dart';
import '../widgets/rotate_hint_banner.dart';
import '../widgets/streak_sheets.dart';

/// The Inversion Running drill: play a chord up through its inversions across a
/// full octave, then back down. Self-paced (each correct voicing advances) or
/// tempo mode (advance on the metronome beat after a count-in), with a
/// transposing keyboard so the chord sits at the same visual spot every round
/// regardless of key.
class InversionRunScreen extends StatefulWidget {
  const InversionRunScreen({super.key, required this.midi});

  final MidiService midi;

  @override
  State<InversionRunScreen> createState() => _InversionRunScreenState();
}

class _InversionRunScreenState extends State<InversionRunScreen> {
  InversionRunController? _controller;
  QuizSettings? _settings;
  MetronomeController? _metronome;
  bool _noteSound = true;
  bool _tempoMode = false;
  bool _showDots = true;
  bool _showFormula = true;
  final NotePlayer _notes = NotePlayer();

  /// Live MIDI setup changes, so the latency correction can be
  /// re-resolved when a keyboard connects after this screen opened.
  StreamSubscription<String>? _setupSub;

  /// The transposing keyboard needs ~2 octaves: root → octave-root + the maj7
  /// above it (≈23 semitones). Two octaves (24 semitones span) covers it.
  static const int _keyboardOctaves = 2;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final settings = await QuizSettings.load();
    final metronome = MetronomeController(
      bpm: await settings.metronomeBpm(),
      onBpmChanged: settings.setMetronomeBpm,
    );
    // Collapsing the metronome bar stops the clock; the tempo drill can't run
    // without it, so stop the controller too.
    metronome.addListener(() {
      final c = _controller;
      if (!metronome.running &&
          c != null &&
          _tempoMode &&
          c.phase != InversionPhase.idle) {
        c.stop();
      }
    });
    _metronome = metronome;
    _settings = settings;
    await _rebuildController();
    // The correction is looked up per connected device. A keyboard still
    // auto-reconnecting when this screen opened would otherwise leave the
    // whole session judged at 0 ms, so re-resolve on every setup change.
    _setupSub = widget.midi.onSetupChanged.listen((_) => _refreshLatency());
  }

  /// Re-resolve the input-latency correction for whatever is connected now
  /// and apply it live. Deliberately does NOT rebuild the controller: that
  /// would reset a run in progress. Both the judge and the metronome flash
  /// read the field per press, so a late update takes effect immediately.
  Future<void> _refreshLatency() async {
    final settings = _settings;
    if (settings == null) return;
    final latency = await resolveInputLatencyMs(widget.midi, settings);
    if (!mounted) return;
    _controller?.inputLatencyMs = latency;
    _metronome?.inputLatencyMs = latency;
  }

  Future<void> _rebuildController() async {
    final settings = _settings;
    final metronome = _metronome;
    if (settings == null || metronome == null) return;
    metronome.stop();
    _noteSound = await settings.noteSoundEnabled();
    _tempoMode = await settings.invTempoMode();
    _showDots = await settings.invShowDots();
    _showFormula = await settings.invShowFormula();
    final chords = await settings.invEnabledChords();
    final difficulty = await settings.timingDifficulty();
    final hapticEnabled = await settings.tickHapticEnabled();
    final old = _controller;
    final next = InversionRunController(
      chords: chords,
      tempoMode: _tempoMode,
      onBeatMs: difficulty.onBeatMs,
      closeMs: difficulty.closeMs,
    );
    final latency = await resolveInputLatencyMs(widget.midi, settings);
    next
      ..msSinceBeat = (() => metronome.msSinceLastTick)
      ..beatPeriodMs = (() => metronome.beatPeriodMs)
      ..inputLatencyMs = latency
      ..onAnyPress = (note) {
        if (_noteSound) _notes.play(note);
        if (_tempoMode && next.running) metronome.registerHit();
      }
      ..onSessionEnd = () => _endSession(next);
    metronome
      ..inputLatencyMs = latency
      ..onBeatMs = difficulty.onBeatMs
      ..closeMs = difficulty.closeMs
      ..hapticEnabled = hapticEnabled
      ..onBeat = next.onBeat;
    next.bindMidi(widget.midi);
    if (!mounted) {
      next.dispose();
      return;
    }
    setState(() => _controller = next);
    old?.dispose();
  }

  void _toggleRun() {
    final c = _controller;
    final m = _metronome;
    if (c == null || m == null) return;
    if (c.phase == InversionPhase.idle) {
      // Not every reconnect emits a setup change (app resume and launch
      // restore don't), so catch up here too — by Start the keyboard is
      // connected in practice, and the count-in bar covers the async read.
      unawaited(_refreshLatency());
      c.start();
      if (_tempoMode) m.start();
    } else {
      c.stop();
      m.stop();
    }
  }

  /// A session has ended (manual stop, or metronome collapse in tempo mode):
  /// snapshot its stats, fold them into the persisted lifetime aggregates,
  /// and show the summary. Guarded so it runs once and only when something
  /// was actually judged.
  bool _endingSession = false;
  Future<void> _endSession(InversionRunController c) async {
    final stats = InversionSessionStats.from(c);
    if (_endingSession || !stats.hasData) return;
    _endingSession = true;
    final settings = _settings;
    if (settings != null) {
      await settings.mergeInversionStats(c.chordSnapshot);
      unawaited(
          SocialService.instance.recordWeeklySessionFrom(c.chordSnapshot));
      unawaited(SocialService.instance.recordModeScores());
    }
    final streakUpdate = await StreakService.instance.recordPractice();
    if (mounted) {
      await InversionSessionSummarySheet.show(context, stats);
    }
    if (streakUpdate.milestone case final m? when mounted) {
      await StreakMilestoneSheet.show(context, m);
    }
    if (mounted) {
      await PaywallSheet.maybeShowAfterTrial(
          context, settings, QuizSettings.modeInversionRun);
    }
    if (mounted) await ReminderPromptSheet.maybeShow(context);
    _endingSession = false;
  }

  Future<void> _openSettings() async {
    final settings = _settings;
    if (settings == null) return;
    await InversionRunSettingsSheet.show(
      context,
      settings: settings,
      onChanged: _rebuildController,
    );
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _setupSub?.cancel();
    _controller?.dispose();
    _metronome?.dispose();
    _notes.dispose();
    super.dispose();
  }

  static const double _topBarHeight = 44;

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      body: controller == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                AnimatedBuilder(
                  animation: controller,
                  builder: (context, _) {
                    final bodyHeight = MediaQuery.of(context).size.height;
                    final compact = isCompactLayout(bodyHeight);
                    final maxKeyHeight = isDesktopPlatform ? 320.0 : 240.0;
                    final keyboardHeight = compact
                        ? (bodyHeight * 0.40).clamp(120.0, maxKeyHeight)
                        : (bodyHeight * 0.46).clamp(140.0, maxKeyHeight);
                    return SafeArea(
                      bottom: false,
                      child: Column(
                        children: [
                          const SizedBox(height: _topBarHeight),
                          if (_settings != null)
                            RotateHintBanner(settings: _settings!),
                          Expanded(child: _buildPrompt(controller, compact)),
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
            if (_tempoMode && _metronome != null)
              MetronomeBar(controller: _metronome!),
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
              tooltip: 'Inversion Running settings',
              onPressed: _openSettings,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrompt(InversionRunController c, bool compact) {
    final info = <Widget>[
      Text(
        'Play the chord up through its inversions, then back down',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: AppColors.textSecondary,
          fontSize: compact ? 12 : 14,
        ),
      ),
      SizedBox(height: compact ? 6 : 12),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: ShaderMask(
          shaderCallback: (bounds) =>
              AppColors.accentGradient.createShader(bounds),
          child: Text(
            c.chordLabel,
            style: TextStyle(
              fontSize: compact ? 26 : (isDesktopPlatform ? 36 : 32),
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1.1,
            ),
          ),
        ),
      ),
      if (_showFormula) ...[
        SizedBox(height: compact ? 2 : 4),
        Text(
          c.formulaLabel,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: compact ? 12 : 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ],
      SizedBox(height: compact ? 4 : 6),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          c.running
              ? c.stepLabel
              : c.countingIn
              ? 'Count-in…'
              : 'Press Start',
          style: TextStyle(
            fontSize: compact ? 15 : 18,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      if (c.running) ...[
        const SizedBox(height: 4),
        Text(
          'Step ${c.stepIndex + 1} of ${c.stepCount}',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      ],
    ];
    final status = <Widget>[
      _buildStepDots(c),
      SizedBox(height: compact ? 10 : 14),
      _buildRunControl(c),
    ];
    final child = compact
        ? Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Column(mainAxisSize: MainAxisSize.min, children: info),
              ),
              const SizedBox(width: 28),
              Column(mainAxisSize: MainAxisSize.min, children: status),
            ],
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [...info, const SizedBox(height: 14), ...status],
          );
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: 20,
          vertical: compact ? 4 : 8,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [child],
          ),
        ),
      ),
    );
  }

  /// One dot per cycle step; the apex (octave root) is drawn larger. In tempo
  /// mode each dot fills with its beat verdict color; self-paced fills the
  /// completed steps. The current step is ringed.
  Widget _buildStepDots(InversionRunController c) {
    final count = c.stepCount;
    final apex = count ~/ 2; // middle step is the octave-up root
    final active = c.running || c.countingIn;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: i == apex ? 16 : 12,
            height: i == apex ? 16 : 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _dotColor(c, i),
              border: Border.all(
                color: active && i == c.stepIndex
                    ? AppColors.accent
                    : AppColors.border,
                width: active && i == c.stepIndex ? 2 : 1,
              ),
            ),
            child: _dotIcon(c, i),
          ),
        ],
      ],
    );
  }

  Color _dotColor(InversionRunController c, int i) {
    if (!c.running) return Colors.transparent;
    if (_tempoMode) {
      return switch (c.resultAt(i)) {
        StepResult.onBeat => AppColors.correct,
        StepResult.close => AppColors.accent2,
        StepResult.missed => AppColors.wrong,
        null => Colors.transparent,
      };
    }
    return i < c.stepIndex ? AppColors.correct : Colors.transparent;
  }

  /// A glyph inside the dot so a tempo-mode result never reads by color alone
  /// (colorblind-safe): check = on-beat, dash = close, x = missed. Self-paced
  /// mode only ever marks "completed" (no error state), so it stays plain.
  Widget? _dotIcon(InversionRunController c, int i) {
    if (!_tempoMode || !c.running) return null;
    return switch (c.resultAt(i)) {
      StepResult.onBeat => const Icon(
        Icons.check,
        size: 11,
        color: AppColors.bg,
      ),
      StepResult.close => const Icon(
        Icons.remove,
        size: 11,
        color: AppColors.bg,
      ),
      StepResult.missed => const Icon(
        Icons.close,
        size: 11,
        color: AppColors.bg,
      ),
      null => null,
    };
  }

  Widget _buildRunControl(InversionRunController c) {
    if (c.phase == InversionPhase.idle) {
      return FilledButton.icon(
        onPressed: _toggleRun,
        icon: const Icon(Icons.play_arrow),
        label: const Text('Start'),
      );
    }
    if (c.phase == InversionPhase.countingIn) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${c.beatsUntilDownbeat}',
            style: const TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w800,
              color: AppColors.accent2,
              fontFeatures: tabularFigures,
            ),
          ),
          const Text(
            'Get ready…',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _stat('Streak', '${c.streak}', AppColors.accent2),
        const SizedBox(width: 10),
        _stat('Best', '${c.bestStreak}', AppColors.target),
        const SizedBox(width: 10),
        _stat('Cycles', '${c.cyclesCompleted}', AppColors.correct),
        const SizedBox(width: 14),
        OutlinedButton.icon(
          onPressed: _toggleRun,
          icon: const Icon(Icons.stop, size: 18),
          label: const Text('Stop'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
            side: const BorderSide(color: AppColors.border),
          ),
        ),
      ],
    );
  }

  Widget _stat(String label, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
            fontFeatures: tabularFigures,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _buildKeyboard(InversionRunController c, double height) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: SizedBox(
          height: height,
          child: RepaintBoundary(
            child: PianoKeyboard(
              // Transposing: lowest key is the round's root, fixed display octave.
              lowMidi: c.lowMidi,
              octaves: _keyboardOctaves.toDouble(),
              feedbackFor: c.feedbackFor,
              isTargetHint: (_showDots && (c.running || c.countingIn))
                  ? c.isTargetHint
                  : (_) => false,
              onKeyDown: c.pressKey,
              onKeyUp: c.releaseKey,
            ),
          ),
        ),
      ),
    );
  }
}
