import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// How close a key press landed to the nearest metronome beat.
enum BeatAccuracy { onBeat, close, off }

/// Owns the metronome state (tempo, ticking, beat-timing judgment) so the
/// quiz screen can feed it key presses while [MetronomeBar] renders it.
///
/// Drift-free: beats are scheduled at absolute ideal times against a fixed
/// epoch ([clock.now] at [start]), each tick arming a one-shot timer for the
/// next ideal time. A timer that fires late shortens the next delay instead of
/// pushing every following beat back, so error never accumulates — and timing
/// judgment compares against the *ideal* beat time, not the jittery moment the
/// timer happened to fire.
class MetronomeController extends ChangeNotifier {
  MetronomeController({this._bpm = 100, this.onBpmChanged, bool silent = false})
      : _player = silent ? null : _makePlayer();

  static const minBpm = 40;
  static const maxBpm = 240;

  /// Reports tempo changes (e.g. to persist them).
  final ValueChanged<int>? onBpmChanged;

  /// Estimated input latency (ms) from key-strike to event, subtracted from
  /// each hit before judging so the flash matches when the key was really
  /// pressed. Mirrors ScaleRunController.inputLatencyMs; set per transport.
  int inputLatencyMs = 0;

  /// Timing windows (ms) for [registerHit]'s green/amber/red verdicts, set by
  /// the screen from the global timing-difficulty setting.
  int onBeatMs = 70;
  int closeMs = 150;

  /// Whether each tick buzzes the device, set by the screen from the global
  /// haptic-tick setting. Default on.
  bool hapticEnabled = true;

  /// Fired on every audible tick — lets a beat-driven drill (Scale Running)
  /// share this exact clock so judged beats and the click never drift apart.
  void Function()? onBeat;

  int _bpm;
  bool _running = false;
  Timer? _timer;
  Timer? _flashTimer;
  BeatAccuracy? _flash;

  // Absolute-time scheduling state: everything is measured in ms since _epoch.
  DateTime? _epoch;
  int _lastIdealTickMs = 0; // ideal time of the most recent tick
  int _nextIdealTickMs = 0; // ideal time the armed timer is aiming for

  // Low-latency player preloaded with the click so each tick only seeks+plays.
  // Null when constructed silent (tests), which also skips haptics.
  final AudioPlayer? _player;

  static AudioPlayer _makePlayer() => AudioPlayer()
    ..setPlayerMode(PlayerMode.lowLatency)
    ..setReleaseMode(ReleaseMode.stop)
    ..setSource(AssetSource('audio/click.wav'));

  int get bpm => _bpm;
  bool get running => _running;

  /// Transient timing verdict for the most recent key press (null = no flash).
  BeatAccuracy? get flash => _flash;

  int get _periodMs => 60000 ~/ _bpm;

  /// Beat period in ms at the current tempo (for external timing judgment).
  int get beatPeriodMs => _periodMs;

  /// Ms elapsed since the epoch set at [start] (0 when never started).
  int get _elapsedMs {
    final epoch = _epoch;
    if (epoch == null) return 0;
    return clock.now().difference(epoch).inMilliseconds;
  }

  /// Milliseconds since the most recent tick's *ideal* time (0 when not yet
  /// ticking). Judging against the ideal beat keeps timing verdicts honest
  /// even when the OS fires the tick timer a little late.
  int get msSinceLastTick =>
      _epoch == null ? 0 : _elapsedMs - _lastIdealTickMs;

  void toggle() => _running ? stop() : start();

  void start() {
    _running = true;
    _epoch = clock.now();
    _lastIdealTickMs = 0;
    _nextIdealTickMs = _periodMs;
    _tickNow(); // the downbeat, at ideal time 0
    _scheduleNext();
    notifyListeners();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    if (_running) {
      _running = false;
      notifyListeners();
    }
  }

  void nudge(int delta) {
    _bpm = (_bpm + delta).clamp(minBpm, maxBpm);
    if (_running) {
      // Rebase: the next beat lands one *new* period after the previous ideal
      // tick, so a tempo change glides instead of stuttering an extra tick.
      _nextIdealTickMs = _lastIdealTickMs + _periodMs;
      _scheduleNext();
    }
    onBpmChanged?.call(_bpm);
    notifyListeners();
  }

  /// Judge a key press against the nearest beat and flash the BPM readout
  /// green / amber / red. No-op when the metronome isn't running.
  void registerHit() {
    if (!_running || _epoch == null) return;
    // Subtract input latency before judging so the flash reflects when the key
    // was struck, not when we received the event. Wrap into [0, period).
    final raw = msSinceLastTick - inputLatencyMs;
    final since = ((raw % _periodMs) + _periodMs) % _periodMs;
    final offBy = math.min(since, _periodMs - since);
    _flash = offBy <= onBeatMs
        ? BeatAccuracy.onBeat
        : offBy <= closeMs
            ? BeatAccuracy.close
            : BeatAccuracy.off;
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 350), () {
      _flash = null;
      notifyListeners();
    });
    notifyListeners();
  }

  /// Arm a one-shot timer for the next ideal tick time. A late previous fire
  /// yields a shorter delay (clamped at 0), so lag never accumulates.
  void _scheduleNext() {
    _timer?.cancel();
    final delay = _nextIdealTickMs - _elapsedMs;
    _timer = Timer(Duration(milliseconds: delay < 0 ? 0 : delay), _onTimer);
  }

  void _onTimer() {
    if (!_running) return;
    _lastIdealTickMs = _nextIdealTickMs;
    _nextIdealTickMs += _periodMs;
    _tickNow();
    _scheduleNext();
  }

  void _tickNow() {
    _player
      ?..seek(Duration.zero)
      ..resume();
    if (_player != null && hapticEnabled) HapticFeedback.lightImpact();
    onBeat?.call();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _flashTimer?.cancel();
    _player?.dispose();
    super.dispose();
  }
}

/// Compact metronome for the quiz top bar: a single icon that expands into
/// play/stop + tempo controls when tapped. Stops ticking when collapsed.
class MetronomeBar extends StatefulWidget {
  const MetronomeBar({super.key, required this.controller});

  final MetronomeController controller;

  @override
  State<MetronomeBar> createState() => _MetronomeBarState();
}

class _MetronomeBarState extends State<MetronomeBar> {
  bool _expanded = false;

  void _toggleExpanded() {
    setState(() => _expanded = !_expanded);
    if (!_expanded) widget.controller.stop();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.av_timer),
          color: _expanded ? AppColors.accent : AppColors.textPrimary,
          tooltip: 'Metronome',
          onPressed: _toggleExpanded,
        ),
        // Grows/shrinks smoothly as the controls appear.
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: _expanded
              ? ListenableBuilder(
                  listenable: widget.controller,
                  builder: (context, _) => _controls(widget.controller),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  static Color _bpmColor(BeatAccuracy? flash) => switch (flash) {
        BeatAccuracy.onBeat => AppColors.correct,
        BeatAccuracy.close => AppColors.accent2,
        BeatAccuracy.off => AppColors.wrong,
        null => AppColors.textPrimary,
      };

  Widget _controls(MetronomeController m) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _btn(
            m.running ? Icons.stop : Icons.play_arrow,
            m.running ? 'Stop' : 'Start',
            m.toggle,
            color: m.running ? AppColors.accent : AppColors.textPrimary,
          ),
          _btn(Icons.remove, 'Slower', () => m.nudge(-5)),
          // Flashes green/amber/red with the timing of each key press.
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 100),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: _bpmColor(m.flash),
            ),
            child: Text('${m.bpm}'),
          ),
          _btn(Icons.add, 'Faster', () => m.nudge(5)),
        ],
      ),
    );
  }

  /// IconButton sized to fit the thin 44px top bar.
  Widget _btn(IconData icon, String tooltip, VoidCallback onTap,
      {Color color = AppColors.textSecondary}) {
    return IconButton(
      icon: Icon(icon, size: 18),
      color: color,
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
      onPressed: onTap,
    );
  }
}
