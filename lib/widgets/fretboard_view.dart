import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../quiz/quiz_controller.dart' show KeyFeedback;
import '../theme/app_theme.dart';
import '../theory/fretboard.dart';
import '../theory/music_theory.dart';

/// How the neck is laid out.
enum FretboardOrientation {
  /// Portrait: a chord-diagram box. Strings run top to bottom as columns, the
  /// nut across the top, five frets showing. What fits a phone.
  verticalBox,

  /// Landscape and desktop: a length of neck with the nut at the left.
  horizontalNeck,
}

/// What to draw for the *other* places a target note can be played.
enum TwinDotMode {
  /// Only the position the drill means.
  primaryOnly,

  /// The position the drill means, plus a hollow ring on every twin. Default:
  /// it teaches the neck without turning a scale into confetti.
  primaryAndGhost,

  /// Every position, filled. For players who already read the whole neck.
  all,
}

/// An interactive fretboard that stands in for the on-screen piano.
///
/// Same four callbacks, so validators, judging, scoring and stats never learn
/// which instrument is on screen. What it adds is the thing a piano does not
/// have: one note lives in several places at once. A tap is still
/// unambiguous — a cell is exactly one note — but the *display* is
/// one-to-many, so everything is anchored to [box], and [twinMode] decides how
/// much of the rest of the neck to admit to.
///
/// Input goes through a raw [Listener] rather than per-cell gesture detectors,
/// because a chord is several fingers down at once and the widget has to track
/// pointers itself. Two consequences worth knowing:
///
///  * Notes are ref-counted. Fret 5 of the A string and the open D string are
///    both MIDI 50; lifting one finger must not release a note the other is
///    still holding.
///  * A string already under a finger ignores a second one, the way a real
///    string can only sound one note.
class FretboardView extends StatefulWidget {
  const FretboardView({
    super.key,
    required this.box,
    required this.feedbackFor,
    required this.isTargetHint,
    required this.onKeyDown,
    required this.onKeyUp,
    this.tuning = Tuning.standard,
    this.orientation = FretboardOrientation.verticalBox,
    this.leftHanded = false,
    this.twinMode = TwinDotMode.primaryAndGhost,
    this.showLabels = true,
  });

  /// The window of frets on screen. Drills slide it with [boxFor].
  final FretBox box;

  final KeyFeedback Function(int midiNote) feedbackFor;
  final bool Function(int midiNote) isTargetHint;
  final ValueChanged<int> onKeyDown;
  final ValueChanged<int> onKeyUp;

  final Tuning tuning;
  final FretboardOrientation orientation;

  /// Mirrors the string order (and only the string order — frets still climb
  /// the same way, so "fret 5" is in the same place for both hands).
  final bool leftHanded;

  final TwinDotMode twinMode;
  final bool showLabels;

  @override
  State<FretboardView> createState() => _FretboardViewState();
}

/// Widest a string may be spaced. Past this the neck stops reading as a neck
/// on a Mac window or an iPad, the same reason the piano caps its width.
const double _maxStringPitch = 60;

/// Widest a fret may be spaced, for the same reason.
const double _maxFretPitch = 72;

/// Matches the piano's key animation exactly, so feedback reads identically
/// whichever surface is on screen.
const Duration _glowDuration = Duration(milliseconds: 90);

/// Frets that carry a position marker; 12 gets the double dot.
const Set<int> _inlayFrets = {3, 5, 7, 9, 12, 15, 17, 19, 21};

class _FretboardViewState extends State<FretboardView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: _glowDuration,
    value: 1,
  );

  /// Pointer id to the cell it is holding. A pointer that landed on a busy
  /// string is absent, so its release is a no-op.
  final Map<int, FretPosition> _pointers = {};

  /// MIDI note to how many pointers are holding it. See the class doc.
  final Map<int, int> _refs = {};

  Map<FretPosition, Color> _from = const {};
  Map<FretPosition, Color> _to = const {};

  _Geometry? _geometry;

  @override
  void dispose() {
    _glow.dispose();
    super.dispose();
  }

  // ---- Input -------------------------------------------------------------

  /// Records the press. Returns the note to sound, or null when another
  /// finger is already holding that note somewhere else on the neck.
  int? _addPointer(int pointer, FretPosition cell) {
    _pointers[pointer] = cell;
    final midi = cell.midi(widget.tuning);
    final held = (_refs[midi] ?? 0) + 1;
    _refs[midi] = held;
    return held == 1 ? midi : null;
  }

  /// Forgets the press. Returns the note to silence, or null when the pointer
  /// was never holding one or another finger still is.
  int? _removePointer(int pointer) {
    final cell = _pointers.remove(pointer);
    if (cell == null) return null;
    final midi = cell.midi(widget.tuning);
    final held = (_refs[midi] ?? 1) - 1;
    if (held > 0) {
      _refs[midi] = held;
      return null;
    }
    _refs.remove(midi);
    return midi;
  }

  bool _stringIsBusy(int string, {int? ignoring}) => _pointers.entries
      .any((e) => e.key != ignoring && e.value.string == string);

  void _onDown(PointerDownEvent e) {
    final cell = _geometry?.hitTest(e.localPosition);
    // A string already under a finger takes no second one, the way a real
    // string only sounds one note.
    if (cell == null || _stringIsBusy(cell.string)) return;
    final down = _addPointer(e.pointer, cell);
    setState(() {});
    if (down != null) widget.onKeyDown(down);
  }

  void _onMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    final cell = _geometry?.hitTest(e.localPosition);
    if (cell == null || cell == _pointers[e.pointer]) return;
    if (_stringIsBusy(cell.string, ignoring: e.pointer)) return;
    final up = _removePointer(e.pointer);
    final down = _addPointer(e.pointer, cell);
    setState(() {});
    if (up != null) widget.onKeyUp(up);
    if (down != null) widget.onKeyDown(down);
  }

  void _onUp(int pointer) {
    if (!_pointers.containsKey(pointer)) return;
    final up = _removePointer(pointer);
    setState(() {});
    if (up != null) widget.onKeyUp(up);
  }

  // ---- Painting state ----------------------------------------------------

  /// Which cell each sounding note should light.
  ///
  /// A note under a finger lights the cell that finger is on, so the glow
  /// lands where the player is looking. A note arriving from a MIDI guitar or
  /// keyboard has no cell, so it lights the one the drill means.
  Map<FretPosition, Color> _glowTargets() {
    final out = <FretPosition, Color>{};
    final touched = <int, List<FretPosition>>{};
    for (final cell in _pointers.values) {
      touched.putIfAbsent(cell.midi(widget.tuning), () => []).add(cell);
    }
    for (var midi = widget.tuning.lowest;
        midi <= widget.tuning.highest();
        midi++) {
      final colour = _glowColour(widget.feedbackFor(midi));
      if (colour == null) continue;
      final cells = touched[midi];
      if (cells != null) {
        for (final c in cells) {
          out[c] = colour;
        }
      } else {
        final primary = primaryFor(midi, widget.box, tuning: widget.tuning);
        if (primary != null && widget.box.contains(primary.fret)) {
          out[primary] = colour;
        }
      }
    }
    return out;
  }

  /// Hint dots, split into the position the drill means and its twins.
  (Set<FretPosition>, Set<FretPosition>) _hintDots(
      Map<FretPosition, Color> glows) {
    final solid = <FretPosition>{};
    final ghost = <FretPosition>{};
    for (var midi = widget.tuning.lowest;
        midi <= widget.tuning.highest();
        midi++) {
      if (!widget.isTargetHint(midi)) continue;
      final primary = primaryFor(midi, widget.box, tuning: widget.tuning);
      if (primary != null && widget.box.contains(primary.fret)) {
        solid.add(primary);
      }
      if (widget.twinMode == TwinDotMode.primaryOnly) continue;
      for (final p in positionsFor(midi, tuning: widget.tuning)) {
        if (p == primary || !widget.box.contains(p.fret)) continue;
        (widget.twinMode == TwinDotMode.all ? solid : ghost).add(p);
      }
    }
    // A lit cell says everything a dot would, so the dot gets out of the way.
    solid.removeWhere(glows.containsKey);
    ghost.removeWhere((p) => glows.containsKey(p) || solid.contains(p));
    return (solid, ghost);
  }

  Map<FretPosition, Color> _lerpedNow() {
    final t = _glow.value;
    if (t >= 1) return _to;
    return {
      for (final key in {..._from.keys, ..._to.keys})
        key: Color.lerp(
              _from[key] ?? _to[key]!.withValues(alpha: 0),
              _to[key] ?? _from[key]!.withValues(alpha: 0),
              t,
            ) ??
            Colors.transparent,
    };
  }

  @override
  Widget build(BuildContext context) {
    final glows = _glowTargets();
    if (!mapEquals(glows, _to)) {
      _from = _lerpedNow();
      _to = glows;
      // Legal from build: the painter listens via `repaint`, so this schedules
      // a repaint rather than a rebuild.
      _glow.forward(from: 0);
    }
    final (solid, ghost) = _hintDots(glows);

    return LayoutBuilder(
      builder: (context, constraints) {
        final geometry = _Geometry(
          size: _cappedSize(constraints),
          box: widget.box,
          stringCount: widget.tuning.stringCount,
          orientation: widget.orientation,
          leftHanded: widget.leftHanded,
        );
        _geometry = geometry;

        return Center(
          child: SizedBox(
            width: geometry.size.width,
            height: geometry.size.height,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _onDown,
              onPointerMove: _onMove,
              onPointerUp: (e) => _onUp(e.pointer),
              onPointerCancel: (e) => _onUp(e.pointer),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _FretboardPainter(
                        glow: _glow,
                        geometry: geometry,
                        tuning: widget.tuning,
                        from: _from,
                        to: _to,
                        solidDots: solid,
                        ghostDots: ghost,
                        showLabels: widget.showLabels,
                      ),
                    ),
                  ),
                  // One node per cell so a screen reader can walk the neck,
                  // matching the per-key semantics the piano has. These sit
                  // above the painter but absorb nothing: the Listener is
                  // outside and opaque, so it still sees every pointer.
                  for (var s = 0; s < widget.tuning.stringCount; s++)
                    for (var f = widget.box.start; f <= widget.box.end; f++)
                      Positioned.fromRect(
                        rect: geometry.cellRect(s, f),
                        child: Semantics(
                          label: noteName(widget.tuning.midiAt(s, f)),
                          button: true,
                          child: const SizedBox.expand(),
                        ),
                      ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Keep string and fret spacing in a playable range on a wide window, the
  /// fretboard's version of the piano's width cap. On a phone neither cap is
  /// reached and the board fills whatever it is given.
  Size _cappedSize(BoxConstraints constraints) {
    final vertical = widget.orientation == FretboardOrientation.verticalBox;
    final strings = widget.tuning.stringCount * _maxStringPitch;
    final frets = widget.box.width * _maxFretPitch;
    final maxWidth = vertical ? strings : frets;
    final maxHeight = vertical ? frets : strings;
    return Size(
      constraints.hasBoundedWidth
          ? math.min(constraints.maxWidth, maxWidth)
          : maxWidth,
      constraints.hasBoundedHeight
          ? math.min(constraints.maxHeight, maxHeight)
          : maxHeight,
    );
  }
}

Color? _glowColour(KeyFeedback fb) => switch (fb) {
      KeyFeedback.correct => AppColors.correct,
      KeyFeedback.wrong => AppColors.wrong,
      KeyFeedback.pressed => AppColors.accent,
      KeyFeedback.idle => null,
    };

/// Where every cell sits, and which cell a touch belongs to.
///
/// The two axes are named for what they carry rather than for x and y, so one
/// set of rules covers both orientations and the left-handed flip.
class _Geometry {
  _Geometry({
    required this.size,
    required this.box,
    required this.stringCount,
    required this.orientation,
    required this.leftHanded,
  }) : _fretEdges = _edgesFor(box, orientation);

  final Size size;
  final FretBox box;
  final int stringCount;
  final FretboardOrientation orientation;
  final bool leftHanded;

  /// `box.width + 1` boundaries along the fret axis, 0 to 1.
  final List<double> _fretEdges;

  bool get isVertical => orientation == FretboardOrientation.verticalBox;

  /// A real neck's frets crowd together as they climb: fret n sits
  /// `1 - 2^(-n/12)` of the scale length from the nut, the rule of 17.817.
  /// The portrait box ignores it on purpose — a chord diagram is a diagram,
  /// and even spacing buys every fret the same tappable height.
  static List<double> _edgesFor(FretBox box, FretboardOrientation o) {
    if (o == FretboardOrientation.verticalBox) {
      return [for (var i = 0; i <= box.width; i++) i / box.width];
    }
    double distance(int fret) => 1 - math.pow(2, -fret / 12).toDouble();
    // Fret f occupies the space between the lines before and after it. Fret 0
    // is the open string, which has no space of its own, so it borrows fret
    // 1's width on the near side of the nut.
    final leading = box.start == 0
        ? -(distance(1) - distance(0))
        : distance(box.start - 1);
    final raw = [leading, for (var f = box.start; f <= box.end; f++) distance(f)];
    final span = raw.last - raw.first;
    return [for (final r in raw) (r - raw.first) / span];
  }

  double get _acrossExtent => isVertical ? size.width : size.height;
  double get _alongExtent => isVertical ? size.height : size.width;

  /// Slot a string is drawn in, counting along the "across" axis.
  ///
  /// Portrait puts the low E on the left like a chord chart; landscape puts it
  /// at the bottom like the instrument in your lap. Left-handed swaps both.
  int _slotOf(int string) {
    final flipped = isVertical ? leftHanded : !leftHanded;
    return flipped ? stringCount - 1 - string : string;
  }

  double stringCentre(int string) =>
      (_slotOf(string) + 0.5) * (_acrossExtent / stringCount);

  /// Fret [fret]'s band along the "along" axis, as (start, end).
  (double, double) fretBand(int fret) {
    final i = (fret - box.start).clamp(0, box.width - 1);
    return (_fretEdges[i] * _alongExtent, _fretEdges[i + 1] * _alongExtent);
  }

  double fretCentre(int fret) {
    final (a, b) = fretBand(fret);
    return (a + b) / 2;
  }

  Rect cellRect(int string, int fret) {
    final pitch = _acrossExtent / stringCount;
    final across = _slotOf(string) * pitch;
    final (alongStart, alongEnd) = fretBand(fret);
    return isVertical
        ? Rect.fromLTRB(across, alongStart, across + pitch, alongEnd)
        : Rect.fromLTRB(alongStart, across, alongEnd, across + pitch);
  }

  /// Which cell a touch lands on. Bands run edge to edge with no gaps, so
  /// there is nowhere on the board that swallows a tap.
  FretPosition? hitTest(Offset p) {
    final across = isVertical ? p.dx : p.dy;
    final along = isVertical ? p.dy : p.dx;
    if (across < 0 || across > _acrossExtent) return null;
    if (along < 0 || along > _alongExtent) return null;

    final slot =
        (across / (_acrossExtent / stringCount)).floor().clamp(0, stringCount - 1);
    final flipped = isVertical ? leftHanded : !leftHanded;
    final string = flipped ? stringCount - 1 - slot : slot;

    final fraction = (along / _alongExtent).clamp(0.0, 1.0);
    var index = box.width - 1;
    for (var i = 0; i < box.width; i++) {
      if (fraction <= _fretEdges[i + 1]) {
        index = i;
        break;
      }
    }
    return FretPosition(string, box.start + index);
  }
}

class _FretboardPainter extends CustomPainter {
  _FretboardPainter({
    required this.glow,
    required this.geometry,
    required this.tuning,
    required this.from,
    required this.to,
    required this.solidDots,
    required this.ghostDots,
    required this.showLabels,
  }) : super(repaint: glow);

  /// Drives the 90 ms fade between [from] and [to] without a rebuild.
  final Animation<double> glow;

  final _Geometry geometry;
  final Tuning tuning;
  final Map<FretPosition, Color> from;
  final Map<FretPosition, Color> to;
  final Set<FretPosition> solidDots;
  final Set<FretPosition> ghostDots;
  final bool showLabels;

  Color? _glowAt(FretPosition cell) {
    final a = from[cell];
    final b = to[cell];
    if (a == null && b == null) return null;
    return Color.lerp(
      a ?? b!.withValues(alpha: 0),
      b ?? a!.withValues(alpha: 0),
      glow.value,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final g = geometry;
    final box = g.box;

    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = AppColors.surfaceHigh,
    );

    // Fret wire between every pair of bands, and a fat nut when the box sits
    // at the top of the neck.
    final wire = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1.5;
    final nut = Paint()
      ..color = AppColors.textSecondary
      ..strokeWidth = 5;
    for (var f = box.start; f <= box.end; f++) {
      final (start, _) = g.fretBand(f);
      _line(canvas, g, start, f == 1 && box.start == 0 ? nut : wire);
    }
    final (_, tail) = g.fretBand(box.end);
    _line(canvas, g, tail, wire);

    // Position markers, so the eye can find fret 5 or 7 without counting.
    final inlay = Paint()..color = AppColors.border;
    for (var f = box.start; f <= box.end; f++) {
      if (!_inlayFrets.contains(f)) continue;
      final along = g.fretCentre(f);
      final across = g.isVertical ? size.width : size.height;
      final offsets = f == 12 ? [across * 0.3, across * 0.7] : [across * 0.5];
      for (final o in offsets) {
        canvas.drawCircle(
          g.isVertical ? Offset(o, along) : Offset(along, o),
          3,
          inlay,
        );
      }
    }

    // Strings, thicker as they get lower, like the real thing.
    for (var s = 0; s < tuning.stringCount; s++) {
      final centre = g.stringCentre(s);
      final paint = Paint()
        ..color = AppColors.textMuted
        ..strokeWidth = 2.4 - s * 0.25;
      if (g.isVertical) {
        canvas.drawLine(Offset(centre, 0), Offset(centre, size.height), paint);
      } else {
        canvas.drawLine(Offset(0, centre), Offset(size.width, centre), paint);
      }
    }

    // Cells: glow, then dots, then labels.
    for (var s = 0; s < tuning.stringCount; s++) {
      for (var f = box.start; f <= box.end; f++) {
        final cell = FretPosition(s, f);
        final rect = g.cellRect(s, f);
        final radius = math.min(rect.width, rect.height) * 0.32;
        final lit = _glowAt(cell);
        final isLit = lit != null && lit.a > 0.01;
        if (isLit) {
          canvas.drawCircle(
            rect.center,
            radius,
            Paint()
              ..color = lit.withValues(alpha: lit.a * 0.45)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
          );
          canvas.drawCircle(rect.center, radius, Paint()..color = lit);
        } else if (solidDots.contains(cell)) {
          canvas.drawCircle(
            rect.center,
            radius * 0.62,
            Paint()..color = AppColors.target,
          );
        } else if (ghostDots.contains(cell)) {
          canvas.drawCircle(
            rect.center,
            radius * 0.62,
            Paint()
              ..color = AppColors.target.withValues(alpha: 0.55)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5,
          );
        }
        if (showLabels) {
          _label(canvas, rect, tuning.midiAt(s, f), lit: isLit);
        }
      }
    }

    // Which part of the neck this is.
    if (box.start > 0) _fretNumber(canvas, g, size);
  }

  void _line(Canvas canvas, _Geometry g, double along, Paint paint) {
    if (g.isVertical) {
      canvas.drawLine(Offset(0, along), Offset(g.size.width, along), paint);
    } else {
      canvas.drawLine(Offset(along, 0), Offset(along, g.size.height), paint);
    }
  }

  void _label(Canvas canvas, Rect cell, int midi, {required bool lit}) {
    final side = math.min(cell.width, cell.height);
    if (side < 18) return;
    final tp = TextPainter(
      text: TextSpan(
        text: noteName(midi),
        style: TextStyle(
          fontSize: side < 26 ? 8 : 10,
          fontWeight: FontWeight.w600,
          color: lit ? AppColors.bg : AppColors.textMuted,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, cell.center - Offset(tp.width / 2, tp.height / 2));
  }

  void _fretNumber(Canvas canvas, _Geometry g, Size size) {
    final tp = TextPainter(
      text: TextSpan(
        text: '${g.box.start}fr',
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final along = g.fretCentre(g.box.start);
    canvas.drawRect(
      Rect.fromCenter(
        center: g.isVertical ? Offset(6, along) : Offset(along, 8),
        width: tp.width + 4,
        height: tp.height,
      ),
      Paint()..color = AppColors.surfaceHigh,
    );
    tp.paint(
      canvas,
      (g.isVertical ? Offset(6, along) : Offset(along, 8)) -
          Offset(tp.width / 2, tp.height / 2),
    );
  }

  @override
  bool shouldRepaint(_FretboardPainter old) =>
      old.geometry.size != geometry.size ||
      old.geometry.box != geometry.box ||
      old.geometry.leftHanded != geometry.leftHanded ||
      old.geometry.orientation != geometry.orientation ||
      !mapEquals(old.from, from) ||
      !mapEquals(old.to, to) ||
      !setEquals(old.solidDots, solidDots) ||
      !setEquals(old.ghostDots, ghostDots) ||
      old.showLabels != showLabels;
}
