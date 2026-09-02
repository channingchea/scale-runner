import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../audio/note_player.dart';
import '../theme/app_theme.dart';
import '../midi/ble_latency.dart';
import '../midi/midi_service.dart';
import '../purchases/paywall_sheet.dart';
import '../quiz/quiz_controller.dart' show QuizController;
import '../quiz/quiz_settings.dart';
import '../runner/beat_debug.dart';
import '../runner/scale_run_controller.dart';
import '../social/social_service.dart';
import '../streak/streak_service.dart';
import '../theory/fretboard.dart';
import '../ui/responsive.dart';
import '../widgets/fretboard_view.dart' show TwinDotMode;
import '../widgets/instrument_surface.dart';
import '../widgets/metronome_bar.dart';
import '../widgets/rotate_hint_banner.dart';
import '../widgets/reminder_prompt_sheet.dart';
import '../widgets/scale_run_session_summary_sheet.dart';
import '../widgets/scale_run_settings_sheet.dart';
import '../widgets/streak_sheets.dart';

/// The Scale Running drill: a continuous, tempo-driven walk through keys.
/// Hold the diatonic chord in one hand, run its mode in the other — one note
/// per beat, judged against the metronome's clock.
class ScaleRunScreen extends StatefulWidget {
  const ScaleRunScreen({super.key, required this.midi});

  final MidiService midi;

  @override
  State<ScaleRunScreen> createState() => _ScaleRunScreenState();
}

class _ScaleRunScreenState extends State<ScaleRunScreen> {
  ScaleRunController? _controller;
  QuizSettings? _settings;
  bool _showDots = true;
  MetronomeController? _metronome;
  bool _noteSound = true;
  Instrument _instrument = Instrument.piano;
  bool _leftHanded = false;
  TwinDotMode _twinMode = TwinDotMode.primaryAndGhost;
  final NotePlayer _notes = NotePlayer();

  /// Live MIDI setup changes, so the latency correction can be
  /// re-resolved when a keyboard connects after this screen opened.
  StreamSubscription<String>? _setupSub;

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
    // Stopping the metronome (e.g. collapsing its bar) pauses the drill too —
    // the drill cannot run without its clock.
    metronome.addListener(() {
      final c = _controller;
      if (!metronome.running && c != null && c.phase != RunPhase.idle) {
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

  /// (Re)build the controller from the current settings.
  Future<void> _rebuildController() async {
    final settings = _settings;
    final metronome = _metronome;
    if (settings == null || metronome == null) return;
    metronome.stop();
    _noteSound = await settings.noteSoundEnabled();
    _showDots = await settings.runShowDots();
    _instrument = await settings.instrument();
    _leftHanded = await settings.leftHanded();
    _twinMode = await settings.guitarTwinMode();
    final difficulty = await settings.timingDifficulty();
    final hapticEnabled = await settings.tickHapticEnabled();
    final old = _controller;
    final next = ScaleRunController(
      chordsEnabled: await settings.runChordsEnabled(),
      progression: await settings.runProgression(),
      increment: await settings.runKeyIncrement(),
      sevenths: await settings.runSevenths(),
      startKeyPc: await settings.runStartKeyPc(),
      repsPerKey: await settings.runRepsPerKey(),
      onBeatMs: difficulty.onBeatMs,
      closeMs: difficulty.closeMs,
    );
    // Correct for input latency: a saved per-device calibration always wins;
    // otherwise fall back to the BLE default only when the device currently
    // reports as BLE. USB and on-screen taps stay at 0. See
    // resolveInputLatencyMs for why we don't gate purely on isBleConnected.
    final latency = await resolveInputLatencyMs(widget.midi, settings);
    next
      ..msSinceBeat = (() => metronome.msSinceLastTick)
      ..beatPeriodMs = (() => metronome.beatPeriodMs)
      ..inputLatencyMs = latency
      ..onAnyPress = (note) {
        if (_noteSound) _notes.play(note);
        if (next.running) metronome.registerHit();
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
    if (c.phase == RunPhase.idle) {
      // Not every reconnect emits a setup change (app resume and launch
      // restore don't), so catch up here too — by Start the keyboard is
      // connected in practice, and the count-in bar covers the async read.
      unawaited(_refreshLatency());
      c.start(); // start() resets session scores
      m.start();
    } else {
      c.stop(); // fires onSessionEnd → _endSession (snapshot + summary)
      m.stop();
    }
  }

  /// A session has ended (manual stop, metronome collapse, or auto-end at 12
  /// keys): snapshot its stats, fold them into the persisted lifetime
  /// aggregates, and show the summary. Guarded so it runs once and only when
  /// something was actually judged.
  bool _endingSession = false;
  Future<void> _endSession(ScaleRunController c) async {
    final stats = RunSessionStats.from(c);
    if (_endingSession || !stats.hasData) return;
    _endingSession = true;
    // The drill may have auto-ended after the 12th key while the metronome is
    // still ticking — stop it so the clock and drill end together. (The collapse
    // listener won't re-fire onSessionEnd: the controller is already idle.)
    _metronome?.stop();
    final settings = _settings;
    if (settings != null) {
      await settings.mergeRunStats(c.keySnapshot, c.modeSnapshot);
      unawaited(SocialService.instance.recordWeeklySessionFrom(c.keySnapshot));
      unawaited(SocialService.instance.recordModeScores());
    }
    final streakUpdate = await StreakService.instance.recordPractice();
    if (mounted) {
      await ScaleRunSessionSummarySheet.show(context, stats);
    }
    if (streakUpdate.milestone case final m? when mounted) {
      await StreakMilestoneSheet.show(context, m);
    }
    if (mounted) {
      await PaywallSheet.maybeShowAfterTrial(
          context, settings, QuizSettings.modeScaleRun);
    }
    if (mounted) await ReminderPromptSheet.maybeShow(context);
    _endingSession = false;
  }

  Future<void> _openSettings() async {
    final settings = _settings;
    if (settings == null) return;
    await ScaleRunSettingsSheet.show(
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
    // bodyHeight/compact/keyboardHeight only depend on MediaQuery, so they're
    // computed once here (this method already resubscribes to MediaQuery on
    // its own) rather than inside the per-beat builders below. The prompt and
    // keyboard are each wrapped in their own ListenableBuilder — instead of
    // one whole-body AnimatedBuilder — so a key-press glow only rebuilds the
    // keyboard's widgets, not the prompt's text/layout, and vice versa.
    return Scaffold(
      body: controller == null
          ? const Center(child: CircularProgressIndicator())
          : Builder(
              builder: (context) {
                final bodyHeight = MediaQuery.of(context).size.height;
                // Compact mode: landscape PHONES only. Portrait phones and
                // tablets are tall enough for the regular layout.
                final compact = isCompactLayout(bodyHeight);
                final maxKeyHeight = isDesktopPlatform ? 320.0 : 240.0;
                final keyboardHeight = compact
                    ? (bodyHeight * 0.40).clamp(120.0, maxKeyHeight)
                    : (bodyHeight * 0.46).clamp(140.0, maxKeyHeight);
                return Stack(
                  children: [
                    SafeArea(
                      bottom: false,
                      child: Column(
                        children: [
                          const SizedBox(height: _topBarHeight),
                          if (_settings != null)
                            RotateHintBanner(settings: _settings!),
                          Expanded(
                            child: ListenableBuilder(
                              listenable: controller,
                              builder: (context, _) =>
                                  _buildPrompt(controller, compact),
                            ),
                          ),
                          ListenableBuilder(
                            listenable: controller,
                            builder: (context, _) =>
                                _buildKeyboard(
                                    controller, keyboardHeight, compact),
                          ),
                        ],
                      ),
                    ),
                    _buildTopBar(context),
                    if (kBeatDebug)
                      BeatDebugOverlay(
                          listenable: controller, log: () => controller.debug),
                  ],
                );
              },
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
              tooltip: 'Scale Running settings',
              onPressed: _openSettings,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrompt(ScaleRunController c, bool compact) {
    // What to play (labels) and how it's going (dots / chord / controls).
    // Regular layout stacks both groups; compact (landscape-phone) mode puts
    // them side by side so the short viewport isn't asked to fit the full
    // vertical stack.
    final info = <Widget>[
      Text(
        c.chordsEnabled
            ? 'Hold the chord, run the mode: one note per beat'
            : 'Run the scale: one note per beat',
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
            c.keyLabel,
            style: TextStyle(
              fontSize: compact ? 26 : (isDesktopPlatform ? 36 : 32),
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1.1,
            ),
          ),
        ),
      ),
      if (c.repsPerKeyCount > 1) ...[
        SizedBox(height: compact ? 2 : 4),
        Text(
          'rep ${c.repIndex}/${c.repsPerKeyCount}',
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ],
      SizedBox(height: compact ? 4 : 6),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          c.chordsEnabled
              ? '${c.currentStep.chordLabel}  ·  '
                    'run ${c.currentStep.modeLabel}'
              : c.currentStep.modeLabel,
          style: TextStyle(
            fontSize: compact ? 15 : 18,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
        ),
      ),
      if (c.chordsEnabled) ...[
        const SizedBox(height: 4),
        Text(
          'Bar ${c.stepIndex + 1} of ${c.stepCount}'
          '  ·  ${c.progression.name}',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
        ),
      ],
    ];
    final status = <Widget>[
      _buildBeatDots(c),
      SizedBox(height: compact ? 10 : 14),
      if (c.chordsEnabled) ...[
        _buildChordIndicator(c),
        SizedBox(height: compact ? 10 : 14),
      ],
      _buildRunControl(c, compact),
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

  /// The 8 beats of the bar: filled by result color as the run progresses.
  Widget _buildBeatDots(ScaleRunController c) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var b = 0; b < 8; b++) ...[
          if (b > 0) const SizedBox(width: 8),
          AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _dotColor(c.resultAt(b)),
              border: Border.all(
                color: c.running && b == c.beatIndex
                    ? AppColors.accent
                    : AppColors.border,
                width: c.running && b == c.beatIndex ? 2 : 1,
              ),
            ),
            child: _dotIcon(c.resultAt(b)),
          ),
        ],
      ],
    );
  }

  static Color _dotColor(NoteResult? r) => switch (r) {
    NoteResult.onBeat => AppColors.correct,
    NoteResult.close => AppColors.accent2,
    NoteResult.offTime || NoteResult.missed => AppColors.wrong,
    null => Colors.transparent,
  };

  /// A glyph inside the dot so a result never reads by color alone
  /// (colorblind-safe): check = on-beat, dash = close, x = missed/off-time.
  static Widget? _dotIcon(NoteResult? r) => switch (r) {
    NoteResult.onBeat => const Icon(Icons.check, size: 11, color: AppColors.bg),
    NoteResult.close => const Icon(Icons.remove, size: 11, color: AppColors.bg),
    NoteResult.offTime ||
    NoteResult.missed => const Icon(Icons.close, size: 11, color: AppColors.bg),
    null => null,
  };

  /// Confirms the held chord registered — needed because the 2-octave
  /// keyboard means chord and run can overlap in pitch.
  Widget _buildChordIndicator(ScaleRunController c) {
    final held = c.chordHeldCorrectly && c.running;
    final missed = c.chordMissedThisBar;
    final color = missed
        ? AppColors.wrong
        : held
        ? AppColors.correct
        : AppColors.textMuted;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            held ? Icons.check_circle : Icons.radio_button_unchecked,
            color: color,
            size: 16,
          ),
          const SizedBox(width: 6),
          Text(
            missed
                ? 'Chord missed'
                : held
                ? 'Chord held'
                : 'Hold the chord',
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// Start button / count-in number / stop control, by phase.
  Widget _buildRunControl(ScaleRunController c, bool compact) {
    switch (c.phase) {
      case RunPhase.idle:
        return FilledButton.icon(
          onPressed: _toggleRun,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start'),
        );
      case RunPhase.countingIn:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${c.beatsUntilDownbeat}',
              style: TextStyle(
                fontSize: compact ? 30 : 40,
                fontWeight: FontWeight.w800,
                color: AppColors.accent2,
                fontFeatures: tabularFigures,
              ),
            ),
            const Text(
              'Count-in…',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ],
        );
      case RunPhase.running:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _stat('Streak', '${c.streak}', AppColors.accent2),
            const SizedBox(width: 10),
            _stat('Best', '${c.bestStreak}', AppColors.target),
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

  Widget _buildKeyboard(ScaleRunController c, double height, bool compact) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: SizedBox(
          height: height,
          child: RepaintBoundary(
            child: InstrumentSurface(
              instrument: _instrument,
              lowMidi: QuizController.keyboardLowMidi,
              octaves: QuizController.keyboardOctaves.toDouble(),
              anchor: [
                for (var m = QuizController.keyboardLowMidi;
                    m <
                        QuizController.keyboardLowMidi +
                            QuizController.keyboardOctaves * 12;
                    m++)
                  if (c.isTargetHint(m)) m,
              ],
              feedbackFor: c.feedbackFor,
              isTargetHint: _showDots ? c.isTargetHint : (_) => false,
              onKeyDown: c.pressKey,
              onKeyUp: c.releaseKey,
              compact: compact,
              leftHanded: _leftHanded,
              twinMode: _twinMode,
            ),
          ),
        ),
      ),
    );
  }
}
