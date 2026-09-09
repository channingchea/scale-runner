import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theory/fretboard.dart';

/// Slides a [FretBox] along the neck. The drills know which frets they want;
/// Voicing capture and Free Play have no round to follow, so the player moves
/// the window with this.
///
/// [vertical] stacks it into a narrow column for a landscape neck, where there
/// is no height to spare above the board. Up the neck is the top button either
/// way: stacked, that is the spinner convention, and the board's own fret
/// numbers already say which end is the nut.
class FretBoxStepper extends StatelessWidget {
  const FretBoxStepper({
    super.key,
    required this.box,
    required this.onChanged,
    required this.vertical,
  });

  /// Height of the horizontal row above a portrait board.
  static const double rowHeight = 36;

  /// Width of the vertical column beside a landscape neck. A neck lying flat
  /// is already short — spending 36 of its ~164 points on a row above it left
  /// barely 12 points per string — so there it goes down the left edge.
  static const double columnWidth = 46;

  final FretBox box;
  final ValueChanged<FretBox> onChanged;
  final bool vertical;

  void _slide(int by) => onChanged(FretBox(
        (box.start + by).clamp(0, kMaxFret - box.width + 1),
        box.width,
      ));

  @override
  Widget build(BuildContext context) {
    final up = IconButton(
      onPressed: box.end >= kMaxFret ? null : () => _slide(1),
      icon: const Icon(Icons.add, size: 18),
      color: AppColors.textSecondary,
      tooltip: 'Up the neck',
      visualDensity: VisualDensity.compact,
    );
    final down = IconButton(
      onPressed: box.start == 0 ? null : () => _slide(-1),
      icon: const Icon(Icons.remove, size: 18),
      color: AppColors.textSecondary,
      tooltip: 'Toward the nut',
      visualDensity: VisualDensity.compact,
    );
    // "Frets 0-4" does not fit a 46-point column, and beside a board that
    // numbers its own frets the word is redundant anyway.
    final readout = Text(
      vertical ? '${box.start}-${box.end}' : 'Frets ${box.start}-${box.end}',
      textAlign: TextAlign.center,
      style: TextStyle(
        color: AppColors.textSecondary,
        fontSize: vertical ? 11 : 12,
        fontFeatures: tabularFigures,
      ),
    );

    if (vertical) {
      return SizedBox(
        width: columnWidth,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [up, readout, down],
        ),
      );
    }
    return SizedBox(
      height: rowHeight,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [down, SizedBox(width: 74, child: readout), up],
      ),
    );
  }
}
