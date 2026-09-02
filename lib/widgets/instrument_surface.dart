import 'package:flutter/material.dart';

import '../quiz/quiz_controller.dart' show KeyFeedback;
import '../theory/fretboard.dart';
import '../ui/responsive.dart';
import 'fretboard_view.dart';
import 'piano_keyboard.dart';

/// Picks the on-screen input surface for the saved [Instrument] and forwards
/// the same four callbacks either way, so no drill, validator or score has
/// to know which one is on screen.
///
/// [anchor] is the notes that define this round's shape (e.g. the target
/// chord or scale) — piano ignores it and keeps its fixed [lowMidi]/
/// [octaves] span, but the fretboard uses it to pick which five frets to
/// show via [boxFor]. Pass every note the round can highlight, even ones
/// currently hidden by a hint-dots setting, so the box doesn't jump when
/// hints are toggled on.
///
/// [box] overrides that derivation entirely, for the drills where the notes
/// are the wrong thing to derive it from. Two cases: a chord shape wants
/// [boxForShape], since [boxFor] will happily stack two of its notes on one
/// string; and a pitch-class drill wants [boxAtRoot], since the lit set
/// changes every beat and a derived box would walk around under the player.
/// Piano ignores it like everything else here.
class InstrumentSurface extends StatelessWidget {
  const InstrumentSurface({
    super.key,
    required this.instrument,
    required this.lowMidi,
    required this.octaves,
    required this.anchor,
    this.box,
    required this.feedbackFor,
    required this.isTargetHint,
    required this.onKeyDown,
    required this.onKeyUp,
    this.compact = false,
    this.leftHanded = false,
    this.twinMode = TwinDotMode.primaryAndGhost,
    this.showLabels = true,
  });

  final Instrument instrument;
  final int lowMidi;
  final double octaves;
  final List<int> anchor;

  /// The window of frets to show, when the screen knows better than [anchor].
  final FretBox? box;
  final KeyFeedback Function(int midiNote) feedbackFor;
  final bool Function(int midiNote) isTargetHint;
  final ValueChanged<int> onKeyDown;
  final ValueChanged<int> onKeyUp;

  /// Short viewport (landscape phone) — the fretboard lays flat as a neck
  /// instead of standing as a box. Desktop always gets the neck too, below.
  final bool compact;
  final bool leftHanded;
  final TwinDotMode twinMode;
  final bool showLabels;

  @override
  Widget build(BuildContext context) {
    if (instrument == Instrument.piano) {
      return PianoKeyboard(
        lowMidi: lowMidi,
        octaves: octaves,
        feedbackFor: feedbackFor,
        isTargetHint: isTargetHint,
        onKeyDown: onKeyDown,
        onKeyUp: onKeyUp,
        showLabels: showLabels,
      );
    }
    return FretboardView(
      box: box ?? boxFor(anchor),
      feedbackFor: feedbackFor,
      isTargetHint: isTargetHint,
      onKeyDown: onKeyDown,
      onKeyUp: onKeyUp,
      orientation: (compact || isDesktopPlatform)
          ? FretboardOrientation.horizontalNeck
          : FretboardOrientation.verticalBox,
      leftHanded: leftHanded,
      twinMode: twinMode,
      showLabels: showLabels,
    );
  }
}
