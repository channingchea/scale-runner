import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theory/voicings.dart';

/// A postage-stamp keyboard showing the shape of a saved voicing.
///
/// Chord tones are filled in accent teal, and any octave of the voicing's root
/// in amber — so a rootless voicing correctly shows no amber at all, which is
/// exactly the thing worth noticing about it at a glance.
///
/// The strip always starts on a C and ends on a B so it reads as a keyboard
/// rather than an arbitrary slice, widening to whatever the shape spans.
class VoicingThumbnail extends StatelessWidget {
  const VoicingThumbnail({
    super.key,
    required this.spec,
    this.width = 96,
    this.height = 44,
  });

  final VoicingSpec spec;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(painter: _VoicingThumbPainter(spec)),
    );
  }
}

class _VoicingThumbPainter extends CustomPainter {
  _VoicingThumbPainter(this.spec);

  final VoicingSpec spec;

  static const _whiteOffsets = [0, 2, 4, 5, 7, 9, 11];
  static bool _isWhite(int midi) => _whiteOffsets.contains(midi % 12);

  Color _fill(int midi, Color base) {
    if (!_held.contains(midi)) return base;
    return midi % 12 == spec.rootPc ? AppColors.accent2 : AppColors.accent;
  }

  late final List<int> _notes = spec.notesFrom(60);
  late final Set<int> _held = _notes.toSet();

  @override
  void paint(Canvas canvas, Size size) {
    if (_notes.isEmpty) return;
    var low = _notes.first;
    var high = _notes.last;
    while (low % 12 != 0) {
      low--; // open on a C
    }
    while (high % 12 != 11) {
      high++; // close on a B
    }

    final whites = [
      for (var n = low; n <= high; n++)
        if (_isWhite(n)) n,
    ];
    final whiteWidth = size.width / whites.length;
    final blackWidth = whiteWidth * 0.64;
    final blackHeight = size.height * 0.6;
    final radius = Radius.circular(whiteWidth * 0.18);
    final paint = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < whites.length; i++) {
      paint.color = _fill(whites[i], AppColors.whiteKey);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(i * whiteWidth + 0.5, 0, whiteWidth - 1, size.height),
          bottomLeft: radius,
          bottomRight: radius,
        ),
        paint,
      );
    }

    // Black keys sit on the seam between two white keys, so they're indexed by
    // how many white keys precede them.
    var whiteIndex = 0;
    for (var n = low; n < high; n++) {
      if (_isWhite(n)) {
        whiteIndex++;
        continue;
      }
      paint.color = _fill(n, AppColors.blackKey);
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          Rect.fromLTWH(
            whiteIndex * whiteWidth - blackWidth / 2,
            0,
            blackWidth,
            blackHeight,
          ),
          bottomLeft: radius,
          bottomRight: radius,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_VoicingThumbPainter old) => old.spec != spec;
}
