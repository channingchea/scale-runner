import 'dart:async';

import 'package:flutter/material.dart';

import '../onboarding/mode_guides.dart';
import '../quiz/quiz_controller.dart' show KeyFeedback;
import '../theme/app_theme.dart';
import '../theory/fretboard.dart';
import '../theory/music_theory.dart';
import 'fretboard_view.dart' show FretboardLabels, TwinDotMode;
import 'instrument_surface.dart';

/// A looping, non-interactive demo of a mode, played on the same instrument
/// surface the drills use: each [DemoFrame] lights its notes as "correct"
/// (so they read as pressed) and dots its hints, with a caption underneath.
///
/// Piano shows C4..C6, which is the range every script is written in. Guitar
/// lights the frame by pitch class inside a box anchored at its lowest note,
/// so shapes show up wherever the player's fingers would put them.
class GuideDemo extends StatefulWidget {
  const GuideDemo({
    super.key,
    required this.frames,
    required this.instrument,
    this.leftHanded = false,
    this.twinMode = TwinDotMode.primaryAndGhost,
    this.labels = const FretboardLabels(),
    this.height = 120,
  });

  /// Never empty — see the modeGuides data test.
  final List<DemoFrame> frames;
  final Instrument instrument;
  final bool leftHanded;
  final TwinDotMode twinMode;
  final FretboardLabels labels;

  /// Height of the instrument itself; the caption adds a line below.
  final double height;

  /// Piano span for every script: two octaves from C4.
  static const int lowMidi = 60;
  static const double octaves = 2;

  @override
  State<GuideDemo> createState() => _GuideDemoState();
}

class _GuideDemoState extends State<GuideDemo> {
  int _index = 0;
  Timer? _timer;

  /// The most recent non-null caption: frames without one keep it showing.
  String? _caption;

  DemoFrame get _frame => widget.frames[_index];

  @override
  void initState() {
    super.initState();
    _caption = _frame.caption;
    _arm();
  }

  @override
  void didUpdateWidget(GuideDemo old) {
    super.didUpdateWidget(old);
    if (!identical(old.frames, widget.frames)) {
      _index = 0;
      _caption = _frame.caption;
      _arm();
    }
  }

  /// Schedule the hop to the next frame after this one's hold.
  void _arm() {
    _timer?.cancel();
    _timer = Timer(_frame.hold, () {
      if (!mounted) return;
      setState(() {
        _index = (_index + 1) % widget.frames.length;
        _caption = _frame.caption ?? _caption;
      });
      _arm();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  bool _lit(int midi) => widget.instrument == Instrument.piano
      ? _frame.lit.contains(midi)
      : _frame.lit.map(pitchClassOf).contains(pitchClassOf(midi));

  bool _hinted(int midi) => widget.instrument == Instrument.piano
      ? _frame.hints.contains(midi)
      : _frame.hints.map(pitchClassOf).contains(pitchClassOf(midi));

  @override
  Widget build(BuildContext context) {
    final frame = _frame;
    final lowest = frame.lit.isEmpty
        ? (frame.hints.isEmpty
              ? 0
              : frame.hints.reduce((a, b) => a < b ? a : b))
        : frame.lit.reduce((a, b) => a < b ? a : b);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: widget.height,
          width: double.infinity,
          child: IgnorePointer(
            child: InstrumentSurface(
              instrument: widget.instrument,
              lowMidi: GuideDemo.lowMidi,
              octaves: GuideDemo.octaves,
              anchor: frame.hints.toList(),
              box: widget.instrument == Instrument.guitar
                  ? boxAtRoot(pitchClassOf(lowest))
                  : null,
              feedbackFor: (m) =>
                  _lit(m) ? KeyFeedback.correct : KeyFeedback.idle,
              isTargetHint: _hinted,
              onKeyDown: (_) {},
              onKeyUp: (_) {},
              leftHanded: widget.leftHanded,
              twinMode: widget.twinMode,
              labels: widget.labels,
            ),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 18,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: Text(
              _caption ?? '',
              key: ValueKey(_caption),
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
