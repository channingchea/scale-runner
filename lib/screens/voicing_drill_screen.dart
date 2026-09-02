import 'dart:async';

import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../audio/note_player.dart';
import '../midi/midi_service.dart';
import '../quiz/quiz_settings.dart';
import '../runner/voicing_run_controller.dart';
import '../social/social_service.dart';
import '../streak/streak_service.dart';
import '../theme/app_theme.dart';
import '../theory/fretboard.dart';
import '../theory/voicings.dart';
import '../ui/responsive.dart';
import '../widgets/fretboard_view.dart' show TwinDotMode;
import '../widgets/instrument_surface.dart';
import '../widgets/metronome_bar.dart';
import '../widgets/reminder_prompt_sheet.dart';
import '../widgets/rotate_hint_banner.dart';
import '../widgets/streak_sheets.dart';
import '../widgets/voicing_run_settings_sheet.dart';
import '../widgets/voicing_session_summary_sheet.dart';

/// The Voicings drill: one chord shape, walked through every key.
///
/// Self-paced and unscored — a wrong note flashes but never rewinds, and the
/// key doesn't change until the exact shape is played. The keyboard is fixed
/// at C3–C6 for the whole session so the voicing visibly climbs and descends.
///
/// Phase 2 runs a hardcoded shape so the practice loop can be felt on real
/// hardware before any save/collection UI exists; Phase 3 passes [spec] in
/// from the collection screen.
class VoicingDrillScreen extends StatefulWidget {
  const VoicingDrillScreen({super.key, required this.midi, this.spec});

  final MidiService midi;

  /// The voicing to drill. Falls back to a demo shape when absent.
  final VoicingSpec? spec;

  @override
  State<VoicingDrillScreen> createState() => _VoicingDrillScreenState();
}

/// Cmaj7 drop 2 with the 7th in the bass — the plan's reference shape, and the
/// one that exercises negative offsets end to end.
VoicingSpec _demoSpec() => VoicingSpec(
      id: 'demo',
      name: 'Maj7 drop 2',
      rootPc: 0,
      offsets: const [-1, 4, 7, 12],
      createdAt: DateTime.utc(2026),
    );

class _VoicingDrillScreenState extends State<VoicingDrillScreen> {
  VoicingRunController? _controller;
  QuizSettings? _settings;
  MetronomeController? _metronome;
  bool _noteSound = true;
  bool _showDots = true;
  bool _showFormula = true;
  Instrument _instrument = Instrument.piano;
  bool _leftHanded = false;
  TwinDotMode _twinMode = TwinDotMode.primaryAndGhost;
  final NotePlayer _notes = NotePlayer();

  /// The two settings that define the cycle. Kept so a settings change can
  /// tell "restart the drill" apart from "just redraw the hints".
  int _startPc = 0;
  KeyIncrement _increment = KeyIncrement.chromatic;

  /// Set when the player taps "Drill on piano" past a shape no hand can hold
  /// on a neck. Local to this screen — it does not touch the global
  /// Instrument setting, because the answer is about this one voicing.
  bool _pianoOverride = false;

  Instrument get _surface =>
      _pianoOverride ? Instrument.piano : _instrument;

  /// True when the guitar cannot hold this voicing in some key of the cycle.
  ///
  /// Asked of the whole run rather than the current step, so the board does
  /// not vanish and come back mid-drill: a shape is either drillable on a
  /// neck for this cycle or it is not. [VoicingSpec.matches] is
  /// octave-agnostic, so the shape is free to sit wherever [fit] puts it —
  /// but when it puts it nowhere, drawing a degraded box would show dots the
  /// player cannot physically hold together.
  bool get _unplayableOnGuitar {
    final c = _controller;
    if (_surface != Instrument.guitar || c == null) return false;
    return c.steps.any((s) => !fits(s.notes));
  }

  /// Fixed 3-octave keyboard (C3–C6) — wide enough for the shape to climb an
  /// octave and back without transposing the display.
  static const double _keyboardOctaves = 3;
  static const double _topBarHeight = 44;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final settings = await QuizSettings.load();
    // The metronome here is a plain practice click: its onBeat is deliberately
    // left unwired, so nothing about the drill is beat-driven.
    final metronome = MetronomeController(
      bpm: await settings.metronomeBpm(),
      onBpmChanged: settings.setMetronomeBpm,
    )..hapticEnabled = await settings.tickHapticEnabled();
    _noteSound = await settings.noteSoundEnabled();
    _showDots = await settings.voicingShowDots();
    _showFormula = await settings.voicingShowFormula();
    _instrument = await settings.instrument();
    _leftHanded = await settings.leftHanded();
    _twinMode = await settings.guitarTwinMode();
    if (!mounted) {
      metronome.dispose();
      return;
    }
    setState(() {
      _settings = settings;
      _metronome = metronome;
    });
    await _buildController(settings);
  }

  /// (Re)build the drill from the stored key settings. The start key and the
  /// increment define the whole cycle, so there is no way to apply a change to
  /// either except by starting over.
  Future<void> _buildController(QuizSettings settings) async {
    final startPc = await settings.voicingStartKeyPc();
    final increment = await settings.voicingIncrement();
    final next = VoicingRunController(
      spec: widget.spec ?? _demoSpec(),
      startPc: startPc,
      increment: increment,
    );
    next
      ..onAnyPress = (note) {
        if (_noteSound) _notes.play(note);
      }
      ..onSessionEnd = (keys, elapsed) {
        _endSession(next, keys, elapsed);
      };
    next.bindMidi(widget.midi);
    if (!mounted) {
      next.dispose();
      return;
    }
    final old = _controller;
    setState(() {
      _startPc = startPc;
      _increment = increment;
      _controller = next;
    });
    old?.dispose();
  }

  Future<void> _onSettingsChanged() async {
    final settings = _settings;
    if (settings == null) return;
    final showDots = await settings.voicingShowDots();
    final showFormula = await settings.voicingShowFormula();
    final startPc = await settings.voicingStartKeyPc();
    final increment = await settings.voicingIncrement();
    if (!mounted) return;
    setState(() {
      _showDots = showDots;
      _showFormula = showFormula;
    });
    // Toggling a hint mid-run shouldn't throw the run away; changing the keys
    // has to.
    if (startPc != _startPc || increment != _increment) {
      await _buildController(settings);
    }
  }

  Future<void> _openSettings() async {
    final settings = _settings;
    if (settings == null) return;
    await VoicingRunSettingsSheet.show(
      context,
      settings: settings,
      onChanged: _onSettingsChanged,
    );
  }

  /// A session ended — finished, or stopped early. Marks the day for the
  /// streak and shows the summary.
  ///
  /// Note what is *absent*: no accuracy, no mode score, no lifetime-stat
  /// merge, no friend-feed post. `recordWeeklySession(0, 0)` marks the day and
  /// bumps the session count **without** touching attempts or correct, which
  /// is the whole trick behind "counts as practice, but is never scored".
  bool _endingSession = false;

  /// The whole of what a Voicings session writes anywhere. Split out because
  /// backing out of the screen mid-drill has to mark the day too, and there is
  /// no context left to show anything in by then.
  Future<StreakUpdate> _markPractice() {
    unawaited(SocialService.instance.recordWeeklySession(0, 0));
    return StreakService.instance.recordPractice();
  }

  Future<void> _endSession(
    VoicingRunController c,
    int keysCompleted,
    Duration elapsed,
  ) async {
    // Backing out without landing a key isn't practice — it shouldn't claim a
    // streak day, and it shouldn't interrupt with a summary either.
    if (_endingSession || keysCompleted == 0) return;
    _endingSession = true;
    final streakUpdate = await _markPractice();
    var action = VoicingSummaryAction.done;
    if (mounted) {
      action = await VoicingSessionSummarySheet.show(
        context,
        voicingName: c.spec.name,
        formula: c.spec.formula,
        keysCompleted: keysCompleted,
        keyCount: c.stepCount,
        elapsed: elapsed,
      );
    }
    if (streakUpdate.milestone case final m? when mounted) {
      await StreakMilestoneSheet.show(context, m);
    }
    if (mounted) await ReminderPromptSheet.maybeShow(context);
    _endingSession = false;
    if (!mounted) return;
    switch (action) {
      // Guarded: a settings change during the summary would have replaced the
      // controller and disposed this one.
      case VoicingSummaryAction.again when identical(_controller, c):
        c.start();
      case VoicingSummaryAction.pickAnother:
        await Navigator.of(context).maybePop();
      case _:
        break;
    }
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    final c = _controller;
    // Walking away mid-drill was still practice. Mark the day silently — the
    // screen is going, so there's nowhere to show a summary.
    if (c != null && c.running && c.keysCompleted > 0) {
      unawaited(_markPractice());
    }
    c?.dispose();
    _metronome?.dispose();
    _notes.dispose();
    super.dispose();
  }

  static String _fmt(Duration d) =>
      '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

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
                    // Guitar's portrait chord box wants the room a piano
                    // never would: a bigger cell is just easier to tap, and
                    // a tall diagram doesn't look odd the way a tall piano
                    // would.
                    final keyboardHeight = _surface == Instrument.guitar &&
                            !compact
                        ? (bodyHeight * 0.62).clamp(280.0, bodyHeight * 0.72)
                        : compact
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
                          _buildKeyboard(
                              controller, keyboardHeight, compact),
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
              icon: const Icon(Icons.tune),
              color: AppColors.textPrimary,
              tooltip: 'Drill settings',
              onPressed: _settings == null ? null : _openSettings,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrompt(VoicingRunController c, bool compact) {
    final info = <Widget>[
      Text(
        c.spec.name,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: AppColors.textSecondary,
          fontSize: compact ? 12 : 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      SizedBox(height: compact ? 4 : 10),
      FittedBox(
        fit: BoxFit.scaleDown,
        child: ShaderMask(
          shaderCallback: (bounds) =>
              AppColors.accentGradient.createShader(bounds),
          child: Text(
            c.keyLabel,
            style: TextStyle(
              fontSize: compact ? 34 : (isDesktopPlatform ? 52 : 44),
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
            color: AppColors.accent,
            fontSize: compact ? 13 : 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
          ),
        ),
      ],
    ];
    final status = <Widget>[
      _buildProgress(c),
      SizedBox(height: compact ? 10 : 16),
      _buildControl(c),
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
            children: [...info, const SizedBox(height: 18), ...status],
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

  /// A bar rather than a dot per step — 25 dots wouldn't read on a phone.
  Widget _buildProgress(VoicingRunController c) {
    final active = c.running || c.isComplete;
    return SizedBox(
      width: 200,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: active ? c.progress : 0,
              minHeight: 6,
              backgroundColor: AppColors.surfaceHigh,
              valueColor: AlwaysStoppedAnimation(
                c.isComplete ? AppColors.correct : AppColors.accent,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            active ? '${c.stepNumber} / ${c.stepCount}' : '${c.stepCount} keys',
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
              fontFeatures: tabularFigures,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildControl(VoicingRunController c) {
    if (c.isComplete) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${c.keysCompleted} keys · ${_fmt(c.elapsed)}',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              fontFeatures: tabularFigures,
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: c.start,
            icon: const Icon(Icons.refresh),
            label: const Text('Run it again'),
          ),
        ],
      );
    }
    if (!c.running) {
      return FilledButton.icon(
        onPressed: c.start,
        icon: const Icon(Icons.play_arrow),
        label: const Text('Start'),
      );
    }
    return OutlinedButton.icon(
      onPressed: c.stop,
      icon: const Icon(Icons.stop, size: 18),
      label: const Text('Stop'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        side: const BorderSide(color: AppColors.border),
      ),
    );
  }

  Widget _buildKeyboard(
      VoicingRunController c, double height, bool compact) {
    if (_unplayableOnGuitar) {
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.pan_tool_outlined,
                    color: AppColors.textMuted, size: 32),
                const SizedBox(height: 12),
                const Text(
                  'This voicing does not fit under a hand on guitar',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Its notes are spread wider than six strings can hold in '
                  'every key of the cycle.',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(color: AppColors.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => setState(() => _pianoOverride = true),
                  icon: const Icon(Icons.piano_outlined),
                  label: const Text('Drill it on piano'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        child: SizedBox(
          height: height,
          child: RepaintBoundary(
            child: InstrumentSurface(
              instrument: _surface,
              // Fixed for the session — the shape moves, the keyboard doesn't.
              lowMidi: c.lowMidi,
              octaves: _keyboardOctaves,
              anchor: c.currentStep.notes,
              // Drawn where the shape is held, not merely where its notes are
              // reachable. adjacentOnly stays off: an open shape like 1-5-10
              // legitimately skips a string.
              box: _surface == Instrument.guitar
                  ? boxForShape(c.currentStep.notes)
                  : null,
              feedbackFor: c.feedbackFor,
              isTargetHint:
                  (_showDots && c.running) ? c.isTargetHint : (_) => false,
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
