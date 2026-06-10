import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../quiz/quiz_controller.dart';
import '../theory/music_theory.dart';

/// A realistic, responsive on-screen piano.
///
/// Renders [octaves] octaves starting at [lowMidi]. White keys fill the width;
/// black keys are overlaid at their true positions. Each key reports presses
/// and releases via [onKeyDown] / [onKeyUp], and is colored by the
/// [feedbackFor] callback so the same widget serves taps and live-MIDI glow.
///
/// A key "lights up" exactly the same whether pressed on-screen or on the
/// physical keyboard, because both funnel through the controller's held-set.
class PianoKeyboard extends StatelessWidget {
  const PianoKeyboard({
    super.key,
    required this.lowMidi,
    required this.octaves,
    required this.feedbackFor,
    required this.isTargetHint,
    required this.onKeyDown,
    required this.onKeyUp,
    this.showLabels = true,
  });

  final int lowMidi;
  final int octaves;
  final KeyFeedback Function(int midiNote) feedbackFor;
  final bool Function(int midiNote) isTargetHint;
  final ValueChanged<int> onKeyDown;
  final ValueChanged<int> onKeyUp;
  final bool showLabels;

  // Semitone offsets within an octave that are white keys (the rest are black).
  static const _whiteOffsets = [0, 2, 4, 5, 7, 9, 11]; // C D E F G A B

  bool _isWhite(int midi) => _whiteOffsets.contains(midi % 12);

  /// White-key index (0-based) of a white MIDI note, counting from [lowMidi].
  int _whiteIndexOf(int midi) {
    var count = 0;
    for (var n = lowMidi; n < midi; n++) {
      if (_isWhite(n)) count++;
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final highMidi = lowMidi + octaves * 12; // inclusive top C
    final whiteNotes = <int>[];
    for (var n = lowMidi; n <= highMidi; n++) {
      if (_isWhite(n)) whiteNotes.add(n);
    }
    final blackNotes = <int>[];
    for (var n = lowMidi; n < highMidi; n++) {
      if (!_isWhite(n)) blackNotes.add(n);
    }

    // Felt rail above the keys (like a real piano) — anchors the keyboard
    // visually so black keys never blend into the dark background.
    final keys = LayoutBuilder(
      builder: (context, constraints) {
        // Each white key adds 0.5px margin on both sides (1px total). Subtract
        // that from the available width before dividing so the row fits exactly.
        const whiteKeyMargin = 1.0;
        final usableWidth =
            constraints.maxWidth - whiteKeyMargin * whiteNotes.length;
        final whiteWidth = usableWidth / whiteNotes.length;
        final height = constraints.maxHeight;
        final blackWidth = whiteWidth * 0.62;
        final blackHeight = height * 0.62;

        return Stack(
          children: [
            // White keys.
            Row(
              children: [
                for (final midi in whiteNotes)
                  _WhiteKey(
                    midi: midi,
                    width: whiteWidth,
                    height: height,
                    feedback: feedbackFor(midi),
                    isHint: isTargetHint(midi),
                    label: showLabels ? noteName(midi) : null,
                    onDown: () => onKeyDown(midi),
                    onUp: () => onKeyUp(midi),
                  ),
              ],
            ),
            // Black keys overlaid.
            for (final midi in blackNotes)
              Positioned(
                // Center the black key on the gap between its two white keys.
                // Each white key occupies whiteWidth + its 1px margin, so the
                // gap sits at index * (whiteWidth + margin).
                left: _whiteIndexOf(midi) * (whiteWidth + whiteKeyMargin) -
                    blackWidth / 2,
                top: 0,
                child: _BlackKey(
                  midi: midi,
                  width: blackWidth,
                  height: blackHeight,
                  feedback: feedbackFor(midi),
                  isHint: isTargetHint(midi),
                  onDown: () => onKeyDown(midi),
                  onUp: () => onKeyUp(midi),
                ),
              ),
          ],
        );
      },
    );

    return Column(
      children: [
        Container(
          height: 7,
          decoration: const BoxDecoration(
            color: AppColors.felt,
            borderRadius: BorderRadius.vertical(top: Radius.circular(3)),
          ),
        ),
        Expanded(child: keys),
      ],
    );
  }
}

/// Maps a feedback state to the glow color, or null for none.
Color? _glowColor(KeyFeedback fb) {
  switch (fb) {
    case KeyFeedback.correct:
      return AppColors.correct;
    case KeyFeedback.wrong:
      return AppColors.wrong;
    case KeyFeedback.pressed:
      return AppColors.accent;
    case KeyFeedback.idle:
      return null;
  }
}

class _WhiteKey extends StatelessWidget {
  const _WhiteKey({
    required this.midi,
    required this.width,
    required this.height,
    required this.feedback,
    required this.isHint,
    required this.label,
    required this.onDown,
    required this.onUp,
  });

  final int midi;
  final double width;
  final double height;
  final KeyFeedback feedback;
  final bool isHint;
  final String? label;
  final VoidCallback onDown;
  final VoidCallback onUp;

  @override
  Widget build(BuildContext context) {
    final glow = _glowColor(feedback);
    final fillTop = glow ?? AppColors.whiteKey;
    final fillBottom = glow != null
        ? Color.alphaBlend(glow.withValues(alpha: 0.55), AppColors.whiteKey)
        : AppColors.whiteKeyShadow;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => onDown(),
      onTapUp: (_) => onUp(),
      onTapCancel: onUp,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        width: width,
        height: height,
        margin: const EdgeInsets.symmetric(horizontal: 0.5),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [fillTop, fillBottom],
          ),
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(7)),
          boxShadow: glow != null
              ? [BoxShadow(color: glow.withValues(alpha: 0.6), blurRadius: 16, spreadRadius: 1)]
              : null,
          border: Border.all(color: AppColors.whiteKeyShadow, width: 0.5),
        ),
        child: Stack(
          children: [
            if (isHint && feedback == KeyFeedback.idle)
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 22),
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: AppColors.target,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            if (label != null)
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    label!,
                    style: TextStyle(
                      fontSize: width < 26 ? 8 : 10,
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BlackKey extends StatelessWidget {
  const _BlackKey({
    required this.midi,
    required this.width,
    required this.height,
    required this.feedback,
    required this.isHint,
    required this.onDown,
    required this.onUp,
  });

  final int midi;
  final double width;
  final double height;
  final KeyFeedback feedback;
  final bool isHint;
  final VoidCallback onDown;
  final VoidCallback onUp;

  @override
  Widget build(BuildContext context) {
    final glow = _glowColor(feedback);
    final fillTop = glow ?? AppColors.blackKeyTop;
    final fillBottom = glow != null
        ? Color.alphaBlend(Colors.black.withValues(alpha: 0.35), glow)
        : AppColors.blackKey;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => onDown(),
      onTapUp: (_) => onUp(),
      onTapCancel: onUp,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        width: width,
        height: height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [fillTop, fillBottom],
          ),
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(5)),
          boxShadow: glow != null
              ? [BoxShadow(color: glow.withValues(alpha: 0.7), blurRadius: 14, spreadRadius: 1)]
              : const [BoxShadow(color: Colors.black54, blurRadius: 4, offset: Offset(0, 2))],
        ),
        child: isHint && feedback == KeyFeedback.idle
            ? Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: AppColors.target,
                    shape: BoxShape.circle,
                  ),
                ),
              )
            : null,
      ),
    );
  }
}
