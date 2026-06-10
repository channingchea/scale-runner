import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// How close a key press landed to the nearest metronome beat.
enum BeatAccuracy { onBeat, close, off }

/// Owns the metronome state (tempo, ticking, beat-timing judgment) so the
/// quiz screen can feed it key presses while [MetronomeBar] renders it.
class MetronomeController extends ChangeNotifier {
  MetronomeController({this._bpm = 100, this.onBpmChanged});

  static const minBpm = 40;
  static const maxBpm = 240;

  /// Reports tempo changes (e.g. to persist them).
  final ValueChanged<int>? onBpmChanged;

  int _bpm;
  bool _running = false;
  Timer? _timer;
  Timer? _flashTimer;
  DateTime? _lastTick;
  BeatAccuracy? _flash;

  // Low-latency player preloaded with the click so each tick only seeks+plays.
  final _player = AudioPlayer()
    ..setPlayerMode(PlayerMode.lowLatency)
    ..setReleaseMode(ReleaseMode.stop)
    ..setSource(AssetSource('audio/click.wav'));

  int get bpm => _bpm;
  bool get running => _running;

  /// Transient timing verdict for the most recent key press (null = no flash).
  BeatAccuracy? get flash => _flash;

  int get _periodMs => 60000 ~/ _bpm;

  void toggle() => _running ? stop() : start();

  void start() {
    _running = true;
    _restartTimer();
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
    if (_running) _restartTimer(); // apply the new tempo immediately
    onBpmChanged?.call(_bpm);
    notifyListeners();
  }

  /// Judge a key press against the nearest beat and flash the BPM readout
  /// green / amber / red. No-op when the metronome isn't running.
  void registerHit() {
    final last = _lastTick;
    if (!_running || last == null) return;
    final since = DateTime.now().difference(last).inMilliseconds % _periodMs;
    final offBy = math.min(since, _periodMs - since);
    _flash = offBy <= 70
        ? BeatAccuracy.onBeat
        : offBy <= 150
            ? BeatAccuracy.close
            : BeatAccuracy.off;
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 350), () {
      _flash = null;
      notifyListeners();
    });
    notifyListeners();
  }

  void _restartTimer() {
    _timer?.cancel();
    _tick();
    _timer =
        Timer.periodic(Duration(milliseconds: _periodMs), (_) => _tick());
  }

  void _tick() {
    _lastTick = DateTime.now();
    _player
      ..seek(Duration.zero)
      ..resume();
    HapticFeedback.lightImpact();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _flashTimer?.cancel();
    _player.dispose();
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
