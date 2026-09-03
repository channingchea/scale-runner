import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../quiz/quiz_controller.dart' show KeyFeedback;
import '../theme/app_theme.dart';
import '../theory/fretboard.dart';
import '../theory/music_theory.dart';
import '../ui/responsive.dart';

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
  all;

  /// Display name for the settings screen.
  String get label => switch (this) {
        TwinDotMode.primaryOnly => 'Primary only',
        TwinDotMode.primaryAndGhost => 'Primary + ghost',
        TwinDotMode.all => 'All positions',
      };
}

/// The annotations drawn around the board so a player can read it at a
/// glance. All three default on; Settings turns them off individually.
///
/// They are grouped rather than passed as three flags because every drill
/// screen has to carry them from Settings down to the board, and one field
/// per screen is cheaper than three.
class FretboardLabels {
  const FretboardLabels({
    this.strings = true,
    this.fretNumbers = true,
    this.dotsOnly = true,
  });

  /// A gutter naming each open string — E A D G B E in standard tuning.
  final bool strings;

  /// A gutter numbering the window's first fret and any inlay fret inside it.
  /// Off falls back to the old single `5fr` badge painted on the wood.
  final bool fretNumbers;

  /// Narrows note names to lit cells and hint dots. Off names all 30 cells.
  final bool dotsOnly;

  static const none =
      FretboardLabels(strings: false, fretNumbers: false, dotsOnly: false);

  FretboardLabels copyWith({bool? strings, bool? fretNumbers, bool? dotsOnly}) =>
      FretboardLabels(
        strings: strings ?? this.strings,
        fretNumbers: fretNumbers ?? this.fretNumbers,
        dotsOnly: dotsOnly ?? this.dotsOnly,
      );

  @override
  bool operator ==(Object other) =>
      other is FretboardLabels &&
      other.strings == strings &&
      other.fretNumbers == fretNumbers &&
      other.dotsOnly == dotsOnly;

  @override
  int get hashCode => Object.hash(strings, fretNumbers, dotsOnly);
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
    this.labels = const FretboardLabels(),
    this.latched,
    this.onCellDown,
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

  /// Which of the reading aids around the board to draw. See
  /// [FretboardLabels].
  final FretboardLabels labels;

  /// Cells the parent is holding lit with no finger on them.
  ///
  /// Capture is not playing. A tapped note stays on after the finger leaves,
  /// and it has to stay on *the string it was tapped on* — which a MIDI
  /// number cannot say, since a note inside a five-fret box can sit on two
  /// strings at once. So capture keeps its shape as cells and hands it back
  /// here; a cell listed here lights exactly where it is, instead of falling
  /// through to [primaryFor] like a note arriving over MIDI.
  final Set<FretPosition>? latched;

  /// Set to take taps as cells rather than as pitches.
  ///
  /// When this is set the view stops modelling presses at all — no
  /// ref-counting, no one-finger-per-string rule, no [onKeyUp] — and simply
  /// reports the cell tapped. The parent owns the shape and decides what a
  /// second tap on an occupied string means. [onKeyDown] and [onKeyUp] are
  /// not called on touch in this mode.
  final ValueChanged<FretPosition>? onCellDown;

  @override
  State<FretboardView> createState() => _FretboardViewState();
}

/// Widest a string may be spaced on a resizable desktop window. Past this the
/// neck stops reading as a neck. Phones and tablets ignore this cap entirely
/// (see [_FretboardViewState._cappedSize]) — a touch screen is never big
/// enough for a bigger cell to be a bad thing.
const double _maxStringPitch = 60;

/// Widest a fret may be spaced, same desktop-only reasoning.
const double _maxFretPitch = 72;

/// Matches the piano's key animation exactly, so feedback reads identically
/// whichever surface is on screen.
const Duration _glowDuration = Duration(milliseconds: 90);

/// Frets that carry a position marker; 12 gets the double dot.
const Set<int> _inlayFrets = {3, 5, 7, 9, 12, 15, 17, 19, 21};

/// The strip the open-string letters live in, outside the wood. Deliberately
/// outside: on the board they read as part of the instrument rather than as
/// annotation, and they would sit on top of a cell that can be tapped.
const double _stringGutter = 18;

/// The strip the fret numbers live in, on the opposite edge from the letters.
const double _fretGutter = 20;

// ---- Wood palette --------------------------------------------------------
// Decorative only — a rosewood neck, not a semantic app color, so it stays
// local rather than joining AppColors. Feedback/target colors are untouched;
// this only reskins the board itself.
const Color _woodDark = Color(0xFF2E2016);
const Color _woodMid = Color(0xFF4A3323);
const Color _woodLight = Color(0xFF5E4130);
const Color _grainLine = Color(0xFF1E1509);
const Color _boneNut = Color(0xFFE9DFC9);
const Color _nutShadow = Color(0xFFBFB090);
const Color _fretHighlight = Color(0xFFD8DCE2);
const Color _inlayFill = Color(0xFFCDBB93);
const Color _inlayRing = Color(0xFF8D7A55);
const Color _stringHighlight = Color(0xFFDCE0E5);
const Color _stringShadow = Color(0xFF3A3D42);
const Color _labelMuted = Color(0xFFC2B295); // warm, reads on wood

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
    if (cell == null) return;
    final capture = widget.onCellDown;
    if (capture != null) {
      capture(cell);
      return;
    }
    // A string already under a finger takes no second one, the way a real
    // string only sounds one note.
    if (_stringIsBusy(cell.string)) return;
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
    for (final cell in [..._pointers.values, ...?widget.latched]) {
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
        final insets = _gutterInsets();
        final geometry = _Geometry(
          size: _cappedSize(constraints.deflate(insets)),
          box: widget.box,
          stringCount: widget.tuning.stringCount,
          orientation: widget.orientation,
          leftHanded: widget.leftHanded,
        );
        _geometry = geometry;

        // The Listener wraps the board and nothing else. Put it outside the
        // gutters and every tap comes back offset by the gutter size, which
        // looks exactly like a tap-accuracy bug.
        final board = Listener(
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
                    labels: widget.labels,
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
        );

        if (insets == EdgeInsets.zero) {
          return Center(
            child: SizedBox(
              width: geometry.size.width,
              height: geometry.size.height,
              child: board,
            ),
          );
        }

        return Center(
          child: SizedBox(
            width: geometry.size.width + insets.horizontal,
            height: geometry.size.height + insets.vertical,
            child: Stack(
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _GutterPainter(
                        geometry: geometry,
                        tuning: widget.tuning,
                        insets: insets,
                        labels: widget.labels,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: insets.left,
                  top: insets.top,
                  width: geometry.size.width,
                  height: geometry.size.height,
                  child: board,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Space reserved outside the board for the reading aids.
  ///
  /// Portrait runs the letters across the top above the nut and the numbers
  /// down the left; landscape puts the letters at the nut end and the numbers
  /// under the neck. Either way they never share an edge, so the corner
  /// between them stays empty.
  EdgeInsets _gutterInsets() {
    final strings = widget.labels.strings ? _stringGutter : 0.0;
    final frets = widget.labels.fretNumbers ? _fretGutter : 0.0;
    return widget.orientation == FretboardOrientation.verticalBox
        ? EdgeInsets.only(top: strings, left: frets)
        : EdgeInsets.only(left: strings, bottom: frets);
  }

  /// On a resizable desktop window, keep string and fret spacing in a
  /// playable range — the fretboard's version of the piano's width cap.
  /// Phones and tablets get no ceiling at all: touch devices are always
  /// small enough that a bigger cell is strictly better to tap, so in
  /// portrait the box uses all the height its screen gives it, and in
  /// landscape the neck runs edge to edge.
  Size _cappedSize(BoxConstraints constraints) {
    final vertical = widget.orientation == FretboardOrientation.verticalBox;
    final strings = widget.tuning.stringCount * _maxStringPitch;
    final frets = widget.box.width * _maxFretPitch;
    final fallbackWidth = vertical ? strings : frets;
    final fallbackHeight = vertical ? frets : strings;
    if (!isDesktopPlatform) {
      return Size(
        constraints.hasBoundedWidth ? constraints.maxWidth : fallbackWidth,
        constraints.hasBoundedHeight ? constraints.maxHeight : fallbackHeight,
      );
    }
    return Size(
      constraints.hasBoundedWidth
          ? math.min(constraints.maxWidth, fallbackWidth)
          : fallbackWidth,
      constraints.hasBoundedHeight
          ? math.min(constraints.maxHeight, fallbackHeight)
          : fallbackHeight,
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
    required this.labels,
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
  final FretboardLabels labels;

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
    final across = g.isVertical ? size.width : size.height;
    final along = g.isVertical ? size.height : size.width;

    // Wood background: a soft gradient along the neck, plus a handful of
    // long, faint grain streaks running its length.
    final bgRect = Offset.zero & size;
    canvas.drawRect(
      bgRect,
      Paint()
        ..shader = LinearGradient(
          begin: g.isVertical ? Alignment.topLeft : Alignment.topCenter,
          end: g.isVertical ? Alignment.bottomRight : Alignment.bottomCenter,
          colors: const [_woodLight, _woodMid, _woodDark],
        ).createShader(bgRect),
    );
    final grainPaint = Paint()
      ..color = _grainLine.withValues(alpha: 0.16)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    for (final f in const [0.08, 0.26, 0.47, 0.68, 0.88]) {
      final start = g.isVertical ? Offset(f * across, 0) : Offset(0, f * across);
      final mid = g.isVertical
          ? Offset((f + 0.015) * across, along * 0.5)
          : Offset(along * 0.5, (f + 0.015) * across);
      final end =
          g.isVertical ? Offset(f * across, along) : Offset(along, f * across);
      canvas.drawPath(
        Path()
          ..moveTo(start.dx, start.dy)
          ..quadraticBezierTo(mid.dx, mid.dy, end.dx, end.dy),
        grainPaint,
      );
    }

    // Fret wire between every pair of bands — brushed metal — and a bone
    // nut with its own drop shadow where the box sits at the top of the neck.
    final wire = Paint()
      ..color = _fretHighlight.withValues(alpha: 0.85)
      ..strokeWidth = 1.8;
    final nut = Paint()
      ..color = _boneNut
      ..strokeWidth = 6;
    final nutShadow = Paint()
      ..color = _nutShadow.withValues(alpha: 0.7)
      ..strokeWidth = 1.4;
    for (var f = box.start; f <= box.end; f++) {
      final (start, _) = g.fretBand(f);
      if (f == 1 && box.start == 0) {
        _line(canvas, g, start, nut);
        _line(canvas, g, start + 3.2, nutShadow);
      } else {
        _line(canvas, g, start, wire);
      }
    }
    final (_, tail) = g.fretBand(box.end);
    _line(canvas, g, tail, wire);

    // Position markers, so the eye can find fret 5 or 7 without counting.
    final inlayFill = Paint()..color = _inlayFill;
    final inlayRing = Paint()
      ..color = _inlayRing
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var f = box.start; f <= box.end; f++) {
      if (!_inlayFrets.contains(f)) continue;
      final fretAlong = g.fretCentre(f);
      final offsets = f == 12 ? [across * 0.3, across * 0.7] : [across * 0.5];
      for (final o in offsets) {
        final centre =
            g.isVertical ? Offset(o, fretAlong) : Offset(fretAlong, o);
        canvas.drawCircle(centre, 4, inlayFill);
        canvas.drawCircle(centre, 4, inlayRing);
      }
    }

    // Strings: thicker and duller as they get lower (wound bass strings),
    // thinner and brighter toward the top (plain steel), like the real thing.
    for (var s = 0; s < tuning.stringCount; s++) {
      final centre = g.stringCentre(s);
      final t = tuning.stringCount <= 1 ? 1.0 : s / (tuning.stringCount - 1);
      final paint = Paint()
        ..color = Color.lerp(_stringShadow, _stringHighlight, 0.3 + t * 0.55)!
        ..strokeWidth = 2.6 - s * 0.28
        ..strokeCap = StrokeCap.round;
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
        // An empty cell's name is noise: 30 of them turn the board into a
        // wall of text the dots have to fight through. Naming only what the
        // drill is pointing at is what makes the shape read.
        final named = isLit || solidDots.contains(cell) || ghostDots.contains(cell);
        if (showLabels && (named || !labels.dotsOnly)) {
          _label(canvas, rect, tuning.midiAt(s, f), lit: isLit);
        }
      }
    }

    // Which part of the neck this is. The gutter says it better when it is
    // on, and says it at the nut too, where this badge shows nothing.
    if (!labels.fretNumbers && box.start > 0) _fretNumber(canvas, g, size);
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
          color: lit ? AppColors.bg : _labelMuted,
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
      old.showLabels != showLabels ||
      old.labels != labels;
}

/// The reading aids, drawn in the strips [_FretboardViewState._gutterInsets]
/// reserved around the board.
///
/// Kept out of [_FretboardPainter] because that painter's canvas is the board
/// itself: everything it draws is in board-local coordinates, and the gutters
/// are by definition outside them. It also repaints on a different clock —
/// these change only when the window or the settings do, never on a glow.
class _GutterPainter extends CustomPainter {
  _GutterPainter({
    required this.geometry,
    required this.tuning,
    required this.insets,
    required this.labels,
  });

  final _Geometry geometry;
  final Tuning tuning;
  final EdgeInsets insets;
  final FretboardLabels labels;

  @override
  void paint(Canvas canvas, Size size) {
    final g = geometry;

    if (labels.strings) {
      for (var s = 0; s < tuning.stringCount; s++) {
        // The open string's letter, no octave digit — the tester asked for
        // "EADGBE", and E2 vs E4 is not what they were missing. Read off the
        // tuning rather than hardcoded, and placed by the same stringCentre
        // the board uses, so it follows a left-handed flip for free.
        final name = pitchClassNames[pitchClassOf(tuning.openStrings[s])];
        final centre = g.stringCentre(s);
        _text(
          canvas,
          name,
          g.isVertical
              ? Offset(insets.left + centre, insets.top / 2)
              : Offset(insets.left / 2, insets.top + centre),
          weight: FontWeight.w700,
          size: 11,
        );
      }
    }

    if (labels.fretNumbers) {
      // The window's first fret, plus whichever inlays fall inside it. Those
      // are the markers already in the wood, and they are what a player
      // navigates a real neck by, so two or three digits do the job that
      // numbering all five frets would only clutter.
      for (var f = g.box.start; f <= g.box.end; f++) {
        if (f != g.box.start && !_inlayFrets.contains(f)) continue;
        final centre = g.fretCentre(f);
        _text(
          canvas,
          '$f',
          g.isVertical
              ? Offset(insets.left / 2, insets.top + centre)
              : Offset(insets.left + centre,
                  insets.top + g.size.height + insets.bottom / 2),
          weight: f == g.box.start ? FontWeight.w700 : FontWeight.w400,
          size: 10,
        );
      }
    }
  }

  void _text(
    Canvas canvas,
    String text,
    Offset centre, {
    required FontWeight weight,
    required double size,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: size,
          fontWeight: weight,
          color: AppColors.textSecondary,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, centre - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_GutterPainter old) =>
      old.geometry.size != geometry.size ||
      old.geometry.box != geometry.box ||
      old.geometry.leftHanded != geometry.leftHanded ||
      old.geometry.orientation != geometry.orientation ||
      old.insets != insets ||
      old.labels != labels;
}
