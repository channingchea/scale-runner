import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../runner/meter.dart';
import '../theme/app_theme.dart';
import '../ui/responsive.dart';

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
  MetronomeController({
    this._bpm = 100,
    this.onBpmChanged,
    this.onMeterChanged,
    this._meter = Meter.none,
    bool silent = false,
  })  : _player = silent ? null : _makePlayer('audio/click.wav'),
        _accentPlayer = silent ? null : _makePlayer('audio/click_accent.wav');

  static const minBpm = 40;
  static const maxBpm = 240;

  /// Reports tempo changes (e.g. to persist them).
  final ValueChanged<int>? onBpmChanged;

  /// Reports meter changes (e.g. to persist them and resize a count-in).
  final ValueChanged<Meter>? onMeterChanged;

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

  // ---- Meter -------------------------------------------------------------
  Meter _meter;

  /// A meter picked while ticking waits for the bar to end.
  Meter? _pendingMeter;

  /// 0-based beat within the bar; 0 is the accented downbeat.
  int _beatInBar = 0;

  /// The meter in force, or the one about to take over at the next bar.
  Meter get meter => _pendingMeter ?? _meter;

  /// Idle: takes effect at once, from beat 0. Ticking: from the next bar, so
  /// the current one is not cut short.
  set meter(Meter m) {
    if (m == meter) return;
    if (_running) {
      _pendingMeter = m;
    } else {
      _meter = m;
      _beatInBar = 0;
    }
    onMeterChanged?.call(m);
    notifyListeners();
  }

  int get beatInBar => _beatInBar;
  int get barBeats => _meter.beatsPerBar;

  /// Whether the most recent tick (or the coming first tick) is accented.
  bool get accentNow => _meter.accents && _beatInBar == 0;

  /// The tick being delivered right now is beat 1 of a bar. For a drill to
  /// call from its onBeat handler — the accent is chosen after onBeat runs,
  /// so this lands on the very click the drill is reacting to. Scale Running
  /// uses it to restart the cycle on each new scale; the count-ins use it
  /// to line the drill's downbeat up with the accent whatever the metronome
  /// was doing before Start.
  void markDownbeat() => _beatInBar = 0;

  // Absolute-time scheduling state: everything is measured in ms since _epoch.
  DateTime? _epoch;
  int _lastIdealTickMs = 0; // ideal time of the most recent tick
  int _nextIdealTickMs = 0; // ideal time the armed timer is aiming for

  // Low-latency players preloaded with the clicks so each tick only seeks and
  // plays. Both preloaded up front: on Android low-latency mode a sample set
  // at tick time would make the first downbeat late. Null when constructed
  // silent (tests), which also skips haptics.
  final AudioPlayer? _player;
  final AudioPlayer? _accentPlayer;

  static AudioPlayer _makePlayer(String asset) => AudioPlayer()
    ..setPlayerMode(PlayerMode.lowLatency)
    ..setReleaseMode(ReleaseMode.stop)
    ..setSource(AssetSource(asset));

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
    _applyPendingMeter();
    _tickNow(first: true); // the downbeat, at ideal time 0
    _scheduleNext();
    notifyListeners();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _applyPendingMeter();
    if (_running) {
      _running = false;
      notifyListeners();
    }
  }

  void _applyPendingMeter() {
    final m = _pendingMeter;
    if (m == null) return;
    _pendingMeter = null;
    _meter = m;
    _beatInBar = 0;
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

  /// One click. The bar position advances first and the drill hears the
  /// beat next, so a [markDownbeat] from inside its handler still decides
  /// this tick's sound; only then does the click play.
  void _tickNow({bool first = false}) {
    if (first) {
      _beatInBar = 0;
    } else if (_beatInBar + 1 >= barBeats) {
      _applyPendingMeter();
      _beatInBar = 0;
    } else {
      _beatInBar++;
    }
    onBeat?.call();
    final accent = accentNow;
    (accent ? _accentPlayer : _player)
      ?..seek(Duration.zero)
      ..resume();
    if (_player != null && hapticEnabled) {
      accent ? HapticFeedback.mediumImpact() : HapticFeedback.lightImpact();
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _flashTimer?.cancel();
    _player?.dispose();
    _accentPlayer?.dispose();
    super.dispose();
  }
}

/// Compact metronome for the quiz top bar: a single icon that expands into
/// play/stop + tempo + meter controls when tapped. Stops ticking when
/// collapsed.
class MetronomeBar extends StatefulWidget {
  const MetronomeBar({
    super.key,
    required this.controller,
    this.meterLocked = false,
  });

  final MetronomeController controller;

  /// Disables the meter chip. Drill screens lock it while counting in or
  /// running, since a bar that changes length mid-session would desync the
  /// count; the quizzes and Free Play can switch live.
  final bool meterLocked;

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
    // Landscape phones have no height to spare in the pill for the dots.
    final compact = isCompactLayout(MediaQuery.of(context).size.height);
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
          Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Flashes green/amber/red with the timing of each key press.
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 100),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: _bpmColor(m.flash),
                  height: 1.1,
                ),
                child: Text('${m.bpm}'),
              ),
              if (m.meter.accents && !compact) _beatDots(m),
            ],
          ),
          _btn(Icons.add, 'Faster', () => m.nudge(5)),
          _meterChip(m),
        ],
      ),
    );
  }

  /// Where the bar is: one dot per beat, the current one lit, beat 1 bigger.
  Widget _beatDots(MetronomeController m) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < m.barBeats; i++)
            Container(
              width: i == 0 ? 6 : 4,
              height: i == 0 ? 6 : 4,
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i == m.beatInBar
                    ? AppColors.accent
                    : AppColors.textMuted,
              ),
            ),
        ],
      ),
    );
  }

  /// The time-signature picker. Reads "4/4" (or a crossed-out note for No
  /// accent); dimmed and inert while [MetronomeBar.meterLocked].
  Widget _meterChip(MetronomeController m) {
    final locked = widget.meterLocked;
    final color = locked ? AppColors.textMuted : AppColors.textSecondary;
    return PopupMenuButton<Meter>(
      enabled: !locked,
      tooltip: locked ? 'Meter (locked while running)' : 'Meter',
      initialValue: m.meter,
      onSelected: (meter) => m.meter = meter,
      padding: EdgeInsets.zero,
      itemBuilder: (context) => [
        for (final meter in Meter.values)
          PopupMenuItem(
            value: meter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(meter.label),
                if (meter.clicksEighths)
                  const Text(
                    'Each click is an eighth note',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
      ],
      child: Container(
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.center,
        child: m.meter.accents
            ? Text(
                m.meter.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color,
                  fontFeatures: tabularFigures,
                ),
              )
            : Icon(Icons.music_off, size: 16, color: color),
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
