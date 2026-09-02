import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../audio/note_player.dart';
import '../theme/app_theme.dart';
import '../midi/ble_latency.dart';
import '../midi/midi_service.dart';
import '../purchases/paywall_sheet.dart';
import '../quiz/quiz_settings.dart';
import '../runner/beat_debug.dart';
import '../runner/jam_mode_controller.dart';
import '../social/social_service.dart';
import '../streak/streak_service.dart';
import '../theory/fretboard.dart';
import '../ui/responsive.dart';
import '../widgets/fretboard_view.dart' show TwinDotMode;
import '../widgets/instrument_surface.dart';
import '../widgets/jam_mode_settings_sheet.dart';
import '../widgets/jam_session_summary_sheet.dart';
import '../widgets/metronome_bar.dart';
import '../widgets/reminder_prompt_sheet.dart';
import '../widgets/rotate_hint_banner.dart';
import '../widgets/streak_sheets.dart';

/// Jam Mode: a beat-locked diatonic comping drill in one fixed key. The
/// metronome runs continuously; one diatonic chord is prompted per bar and
/// struck on the downbeat. A one-bar count-in arms the drill; stopping the
/// metronome ends the session. Mistakes flash red but the drill never rewinds.
class JamModeScreen extends StatefulWidget {
  const JamModeScreen({super.key, required this.midi});

  final MidiService midi;

  @override
  State<JamModeScreen> createState() => _JamModeScreenState();
}

class _JamModeScreenState extends State<JamModeScreen> {
  JamModeController? _controller;
  QuizSettings? _settings;
  MetronomeController? _metronome;
  bool _noteSound = true;
  bool _showDots = true;
  bool _showFormula = true;
  bool _countInNumbers = true;
  Instrument _instrument = Instrument.piano;
  bool _leftHanded = false;
  TwinDotMode _twinMode = TwinDotMode.primaryAndGhost;
  final NotePlayer _notes = NotePlayer();

  /// Live MIDI setup changes, so the latency correction can be
  /// re-resolved when a keyboard connects after this screen opened.
  StreamSubscription<String>? _setupSub;

  /// This mode widens the keyboard to 2.5 octaves (C3–F5, MIDI 48–77) so a full
  /// maj9 voicing fits in one span. Other modes keep the global 2-octave anchor.
  static const int _keyboardLowMidi = 48; // C3
  static const double _keyboardOctaves = 2.5;

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
    // Jam Mode is always tempo-driven: collapsing the metronome bar stops the
    // clock, which must stop the drill (and surface the session summary).
    metronome.addListener(() {
      final c = _controller;
      if (!metronome.running && c != null && c.phase != JamPhase.idle) {
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
    _showDots = await settings.jamShowDots();
    _showFormula = await settings.jamShowFormula();
    _countInNumbers = await settings.jamCountInNumbers();
    _instrument = await settings.instrument();
    _leftHanded = await settings.leftHanded();
    _twinMode = await settings.guitarTwinMode();
    final keyPc = await settings.jamKeyPc();
    final families = await settings.jamFamilies();
    final sessionBars = await settings.jamSessionBars();
    final freestyle = await settings.jamFreestyle();
    final anyTones = await settings.jamAnyTones();
    final difficulty = await settings.timingDifficulty();
    final hapticEnabled = await settings.tickHapticEnabled();
    final old = _controller;
    final next = JamModeController(
      keyPc: keyPc,
      families: families,
      sessionBars: sessionBars,
      freestyle: freestyle,
      anyTones: anyTones,
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
    if (c.phase == JamPhase.idle) {
      // Not every reconnect emits a setup change (app resume and launch
      // restore don't), so catch up here too — by Start the keyboard is
      // connected in practice, and the count-in bar covers the async read.
      unawaited(_refreshLatency());
      c.resetScores();
      c.start();
      m.start();
    } else {
      c.stop(); // fires onSessionEnd → _endSession (snapshot + summary)
      m.stop();
    }
  }

  /// A session has ended: snapshot its stats, fold them into the persisted
  /// lifetime aggregates, and show the summary. Guarded so it runs once and only
  /// when at least one bar was judged.
  bool _endingSession = false;
  Future<void> _endSession(JamModeController c) async {
    if (_endingSession || c.barsJudged == 0) return;
    _endingSession = true;
    // The drill may have auto-ended after the last chord while the metronome is
    // still ticking — stop it so the clock and drill end together.
    _metronome?.stop();
    final stats = JamSessionStats.from(c);
    final settings = _settings;
    if (settings != null) {
      await settings.mergeJamStats(c.qualitySnapshot, c.degreeSnapshot);
      unawaited(
          SocialService.instance.recordWeeklySessionFrom(c.qualitySnapshot));
      unawaited(SocialService.instance.recordModeScores());
    }
    final streakUpdate = await StreakService.instance.recordPractice();
    if (mounted) {
      await JamSessionSummarySheet.show(context, stats);
    }
    if (streakUpdate.milestone case final m? when mounted) {
      await StreakMilestoneSheet.show(context, m);
    }
    if (mounted) {
      await PaywallSheet.maybeShowAfterTrial(
          context, settings, QuizSettings.modeJam);
    }
    if (mounted) await ReminderPromptSheet.maybeShow(context);
    _endingSession = false;
  }

  Future<void> _openSettings() async {
    final settings = _settings;
    if (settings == null) return;
    await JamModeSettingsSheet.show(
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
    // See ScaleRunScreen.build for why this is split: prompt and keyboard
    // each get their own ListenableBuilder instead of sharing one whole-body
    // AnimatedBuilder, so a beat/key-press update doesn't force the other
    // half to rebuild its widgets too.
    return Scaffold(
      body: controller == null
          ? const Center(child: CircularProgressIndicator())
          : Builder(
              builder: (context) {
                final bodyHeight = MediaQuery.of(context).size.height;
                final compact = isCompactLayout(bodyHeight);
                final maxKeyHeight = isDesktopPlatform ? 320.0 : 240.0;
                // Guitar's portrait chord box wants the room a piano never
                // would: a bigger cell is just easier to tap, and a tall
                // diagram doesn't look odd the way a tall piano would.
                final keyboardHeight = _instrument == Instrument.guitar &&
                        !compact
                    ? (bodyHeight * 0.62).clamp(280.0, bodyHeight * 0.72)
                    : compact
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
              tooltip: 'Jam Mode settings',
              onPressed: _openSettings,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrompt(JamModeController c, bool compact) {
    final active = c.running || c.countingIn;
    final info = <Widget>[
      Text(
        c.keyLabel,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: AppColors.textSecondary,
          fontSize: compact ? 12 : 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
      SizedBox(height: compact ? 6 : 12),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: ShaderMask(
          shaderCallback: (bounds) =>
              AppColors.accentGradient.createShader(bounds),
          child: Text(
            c.running ? c.promptLabel : 'Jam Mode',
            style: TextStyle(
              fontSize: compact ? 26 : (isDesktopPlatform ? 36 : 32),
              fontWeight: FontWeight.w800,
              color: Colors.white,
              height: 1.1,
            ),
          ),
        ),
      ),
      if (c.running && c.freestyle && c.freestyleForbiddenLabel.isNotEmpty) ...[
        SizedBox(height: compact ? 2 : 4),
        Text(
          c.freestyleForbiddenLabel,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: compact ? 12 : 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ] else if (_showFormula &&
          c.running &&
          !c.freestyle &&
          c.currentChord != null) ...[
        SizedBox(height: compact ? 2 : 4),
        Text(
          c.currentChord!.formula,
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: compact ? 12 : 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ],
      SizedBox(height: compact ? 4 : 6),
      _matchedIndicator(c),
      if (c.freestyle && c.running) ...[
        SizedBox(height: compact ? 4 : 6),
        _liveChordPill(c),
      ],
    ];
    final status = <Widget>[
      _countInNumbers
          ? _buildCountInNumber(c, active, compact)
          : _buildBeatDots(c, active),
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

  /// Status pill. Right after a downbeat it shows the verdict (Nailed it / Close
  /// / Missed) so each hit is confirmed; otherwise it tracks whether the chord
  /// is currently built (green) as you prep it during the count-in.
  Widget _matchedIndicator(JamModeController c) {
    final verdict = c.active ? c.lastVerdict : null;
    if (verdict != null) {
      final (label, color, icon) = switch (verdict) {
        JamResult.onBeat => (
          'Nailed it!',
          AppColors.correct,
          Icons.check_circle,
        ),
        JamResult.close => (
          'Close, a bit off',
          AppColors.accent2,
          Icons.timelapse,
        ),
        JamResult.missed => ('Missed', AppColors.wrong, Icons.cancel),
      };
      // Freestyle has no fixed prompt on screen, so name the chord that was
      // actually judged; Prompted already shows it continuously above.
      final judged = c.freestyle ? c.lastJudgedChord : null;
      final full = judged != null ? '$label · ${judged.name}' : label;
      return _pill(full, color, icon, filled: true);
    }
    final matched = c.active && c.currentChordMatched;
    final label = c.active
        ? (matched ? 'Chord ready' : 'Build the chord')
        : 'Press Start';
    return _pill(
      label,
      matched ? AppColors.correct : AppColors.textSecondary,
      matched ? Icons.check_circle : Icons.radio_button_unchecked,
      filled: matched,
    );
  }

  Widget _pill(
    String label,
    Color color,
    IconData icon, {
    required bool filled,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: filled ? color.withValues(alpha: 0.18) : AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: filled ? color : AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: filled ? color : AppColors.textMuted),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: filled ? color : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  /// Freestyle only: live readout of what's currently recognized while
  /// building, so there's feedback before the downbeat. Amber warns the
  /// chord would score a repeat; red warns its family is switched off.
  Widget _liveChordPill(JamModeController c) {
    final match = c.liveChordMatch;
    if (match == null) {
      return _pill('Play any chord', AppColors.textSecondary,
          Icons.radio_button_unchecked, filled: false);
    }
    if (!match.enabled) {
      return _pill('${match.chord.name} · family off', AppColors.wrong,
          Icons.block, filled: true);
    }
    if (c.liveChordIsRepeat) {
      return _pill('${match.chord.name} · repeat', AppColors.accent2,
          Icons.warning_amber_rounded, filled: true);
    }
    return _pill(
        match.chord.name, AppColors.correct, Icons.check_circle, filled: true);
  }

  /// A big decrementing count-in number (4 → 3 → 2 → 1) toward the strike, then
  /// "GO" on the strike/grace beat. Clearer than dots for signalling exactly
  /// when to play the chord.
  Widget _buildCountInNumber(JamModeController c, bool active, bool compact) {
    final size = compact ? 36.0 : 48.0;
    final strike = c.judging;
    final label = !active ? '–' : (strike ? 'GO' : '${c.beatsUntilStrike}');
    final color = strike ? AppColors.accent : AppColors.accent2;
    return SizedBox(
      height: size + 6,
      child: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 90),
          transitionBuilder: (child, anim) =>
              ScaleTransition(scale: anim, child: child),
          child: Text(
            label,
            key: ValueKey(label),
            style: TextStyle(
              fontSize: strike ? size * 0.62 : size,
              fontWeight: FontWeight.w800,
              color: active ? color : AppColors.textMuted,
              height: 1.0,
              fontFeatures: tabularFigures,
            ),
          ),
        ),
      ),
    );
  }

  /// One dot per beat of the bar. The strike lands on the DOWNBEAT (beat 1 —
  /// the first, larger dot); the remaining dots fill as the count-in beats
  /// pass and the current beat is ringed, so you can feel the next downbeat
  /// coming.
  Widget _buildBeatDots(JamModeController c, bool active) {
    final count = c.beatsPerBar;
    final current = active ? c.countInBeat : 0; // 1..count
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: i == 0 ? 16 : 12,
            height: i == 0 ? 16 : 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active && i < current
                  ? (i == 0 ? AppColors.accent : AppColors.accent2)
                  : Colors.transparent,
              border: Border.all(
                color: active && i == current - 1
                    ? AppColors.accent
                    : AppColors.border,
                width: active && i == current - 1 ? 2 : 1,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildRunControl(JamModeController c) {
    if (c.phase == JamPhase.idle) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton.icon(
            onPressed: _toggleRun,
            icon: const Icon(Icons.play_arrow),
            label: Text('Start • ${c.sessionBars} chords'),
          ),
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _stat('Acc', '${(c.accuracy * 100).round()}%', AppColors.correct),
        const SizedBox(width: 10),
        _stat('Streak', '${c.streak}', AppColors.accent2),
        const SizedBox(width: 10),
        _stat('Chord', '${c.barsCompleted}/${c.sessionBars}', AppColors.target),
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

  Widget _buildKeyboard(
      JamModeController c, double height, bool compact) {
    final active = c.running || c.countingIn;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: SizedBox(
          height: height,
          child: RepaintBoundary(
            child: InstrumentSurface(
              instrument: _instrument,
              lowMidi: _keyboardLowMidi,
              octaves: _keyboardOctaves,
              anchor: [
                for (var m = _keyboardLowMidi;
                    m < _keyboardLowMidi + _keyboardOctaves * 12;
                    m++)
                  if (c.isTargetHint(m)) m,
              ],
              feedbackFor: c.feedbackFor,
              isTargetHint: (_showDots && active && c.running)
                  ? c.isTargetHint
                  : (_) => false,
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
