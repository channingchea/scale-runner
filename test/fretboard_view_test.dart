import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scale_runner/quiz/quiz_controller.dart' show KeyFeedback;
import 'package:scale_runner/theory/fretboard.dart';
import 'package:scale_runner/widgets/fretboard_view.dart';

/// The widget is pinned to 300 x 250 at the top left. Most tests here aim
/// taps at coordinates, so they pump with [FretboardLabels.none]: with no
/// gutters reserved the board fills all 300 x 250 and a cell is exactly
/// 50 x 50. The gutter group at the bottom is the one that pumps with them
/// on, and it does its own arithmetic.
const double kCell = 50;

/// Widget size, shared by both.
const double kWidth = 300;
const double kHeight = 250;

void main() {
  late List<int> down;
  late List<int> up;

  setUp(() {
    down = [];
    up = [];
  });

  Future<void> pump(
    WidgetTester tester, {
    FretBox box = const FretBox(0),
    FretboardOrientation orientation = FretboardOrientation.verticalBox,
    bool leftHanded = false,
    TwinDotMode twinMode = TwinDotMode.primaryAndGhost,
    FretboardLabels labels = FretboardLabels.none,
    KeyFeedback Function(int)? feedbackFor,
    bool Function(int)? isTargetHint,
    Set<FretPosition>? latched,
    ValueChanged<FretPosition>? onCellDown,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: kWidth,
          height: kHeight,
          child: FretboardView(
            box: box,
            orientation: orientation,
            leftHanded: leftHanded,
            twinMode: twinMode,
            labels: labels,
            feedbackFor: feedbackFor ?? (_) => KeyFeedback.idle,
            isTargetHint: isTargetHint ?? (_) => false,
            onKeyDown: down.add,
            onKeyUp: up.add,
            latched: latched,
            onCellDown: onCellDown,
          ),
        ),
      ),
    ));
  }

  /// Centre of the cell drawn in string slot [slot] and fret row [row].
  Offset cell(int slot, int row) =>
      Offset((slot + 0.5) * kCell, (row + 0.5) * kCell);

  group('capture mode', () {
    testWidgets('a tap reports the cell, not the pitch', (tester) async {
      final cells = <FretPosition>[];
      await pump(tester, onCellDown: cells.add);
      await tester.tapAt(cell(2, 3)); // D string, fret 3
      await tester.pump();
      expect(cells, [const FretPosition(2, 3)]);
      // The parent owns the shape, so nothing is sounded or released here.
      expect(down, isEmpty);
      expect(up, isEmpty);
    });

    testWidgets('a second tap on a busy string is still reported',
        (tester) async {
      // Playing refuses it (one string sounds one note); capture needs it, so
      // the parent can move that string's note instead of stacking on it.
      final cells = <FretPosition>[];
      await pump(tester, onCellDown: cells.add);
      await tester.tapAt(cell(1, 0));
      await tester.tapAt(cell(1, 4));
      await tester.pump();
      expect(cells, [const FretPosition(1, 0), const FretPosition(1, 4)]);
    });

    testWidgets('a held finger does not lock a string in capture mode',
        (tester) async {
      final cells = <FretPosition>[];
      await pump(tester, onCellDown: cells.add);
      final holding = await tester.startGesture(cell(0, 0), pointer: 1);
      await tester.tapAt(cell(0, 2));
      await tester.pump();
      expect(cells.length, 2);
      await holding.up();
    });

    testWidgets('a latched cell renders without a finger on it',
        (tester) async {
      // MIDI 59 sits on two cells inside frets 0-4: the open B string and the
      // G string at fret 4. Latching pins which one.
      const onG = FretPosition(3, 4);
      expect(onG.midi(), 59);
      expect(primaryFor(59, const FretBox(0)), const FretPosition(4, 0));
      await pump(
        tester,
        latched: {onG},
        feedbackFor: (n) => n == 59 ? KeyFeedback.pressed : KeyFeedback.idle,
      );
      await tester.pump(const Duration(milliseconds: 120));
      expect(tester.takeException(), isNull);
    });
  });

  group('input', () {
    testWidgets('a tap sounds the note at that cell', (tester) async {
      await pump(tester);
      // Slot 0 is the low E string, row 3 is fret 3: MIDI 43.
      await tester.tapAt(cell(0, 3));
      await tester.pump();
      expect(down, [43]);
      expect(up, [43]);
    });

    testWidgets('two fingers on two strings sound two notes', (tester) async {
      await pump(tester);
      final a = await tester.startGesture(cell(0, 0), pointer: 1);
      final b = await tester.startGesture(cell(5, 0), pointer: 2);
      await tester.pump();
      expect(down, [40, 64]); // low E open, high E open
      expect(up, isEmpty);

      await a.up();
      await b.up();
      await tester.pump();
      expect(up, [40, 64]);
    });

    testWidgets('a string under a finger ignores a second one',
        (tester) async {
      await pump(tester);
      final a = await tester.startGesture(cell(2, 0), pointer: 1); // D open, 50
      final b = await tester.startGesture(cell(2, 4), pointer: 2); // same string
      await tester.pump();
      expect(down, [50]);

      await b.up(); // the rejected pointer releases nothing
      await tester.pump();
      expect(up, isEmpty);

      await a.up();
      await tester.pump();
      expect(up, [50]);
    });

    testWidgets('a note in two places is ref-counted, not double-released',
        (tester) async {
      await pump(tester);
      // MIDI 59 is fret 4 of the G string and the open B string, and both are
      // inside a box at the nut.
      expect(Tuning.standard.midiAt(3, 4), 59);
      expect(Tuning.standard.midiAt(4, 0), 59);

      final a = await tester.startGesture(cell(3, 4), pointer: 1);
      final b = await tester.startGesture(cell(4, 0), pointer: 2);
      await tester.pump();
      expect(down, [59], reason: 'the second finger re-sounds nothing');

      await a.up();
      await tester.pump();
      expect(up, isEmpty, reason: 'the other finger is still holding it');

      await b.up();
      await tester.pump();
      expect(up, [59]);
    });

    testWidgets('a cancelled pointer releases its note', (tester) async {
      await pump(tester);
      final g = await tester.startGesture(cell(1, 2), pointer: 1);
      await tester.pump();
      expect(down, [47]); // A string, fret 2
      await g.cancel();
      await tester.pump();
      expect(up, [47]);
    });

    testWidgets('sliding to another cell swaps the note', (tester) async {
      await pump(tester);
      final g = await tester.startGesture(cell(0, 0), pointer: 1);
      await tester.pump();
      expect(down, [40]);
      await g.moveTo(cell(0, 4));
      await tester.pump();
      expect(up, [40]);
      expect(down, [40, 44]);
      await g.up();
      await tester.pump();
      expect(up, [40, 44]);
    });

    testWidgets('a box up the neck taps the frets it shows', (tester) async {
      await pump(tester, box: const FretBox(5));
      await tester.tapAt(cell(0, 0)); // low E, fret 5
      await tester.pump();
      expect(down, [45]);
    });
  });

  group('left-handed', () {
    testWidgets('mirrors the string order and leaves the frets alone',
        (tester) async {
      await pump(tester, leftHanded: true);
      // The same tap that was the low E is now the high E, at the same fret.
      await tester.tapAt(cell(0, 4));
      await tester.pump();
      expect(down, [68]); // high E string, fret 4

      down.clear();
      await pump(tester);
      await tester.tapAt(cell(0, 4));
      await tester.pump();
      expect(down, [44]); // low E string, same fret 4
    });
  });

  group('horizontal neck', () {
    testWidgets('puts the low string at the bottom', (tester) async {
      await pump(tester, orientation: FretboardOrientation.horizontalNeck);
      // Across axis is the height: 250 over 6 strings. The bottom band is the
      // low E; the frets run left to right, widest at the nut.
      await tester.tapAt(const Offset(20, 250 - 250 / 12));
      await tester.pump();
      expect(down.single, lessThan(50), reason: 'expected a low string');

      down.clear();
      await tester.tapAt(const Offset(20, 250 / 12));
      await tester.pump();
      expect(down.single, greaterThan(60), reason: 'expected a high string');
    });
  });

  group('rendering', () {
    testWidgets('draws every twin mode and a lit note without complaint',
        (tester) async {
      for (final mode in TwinDotMode.values) {
        await pump(
          tester,
          twinMode: mode,
          isTargetHint: (m) => m % 12 == 0, // every C
          feedbackFor: (m) => m == 40 ? KeyFeedback.correct : KeyFeedback.idle,
        );
        await tester.pump(const Duration(milliseconds: 120));
        expect(tester.takeException(), isNull, reason: mode.name);
      }
    });

    testWidgets('every cell is reachable by a screen reader', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester);
      // Six strings across five frets.
      expect(find.bySemanticsLabel('E2'), findsOneWidget); // low E open
      expect(find.bySemanticsLabel('G#2'), findsOneWidget); // low E fret 4
      expect(find.bySemanticsLabel('E4'), findsOneWidget); // high E open
      handle.dispose();
    });
  });

  // The gutters reserve space *outside* the board, which means the board no
  // longer starts at the widget's top left. If the Listener is ever hoisted
  // outside them, every tap comes back short by the gutter size — which on a
  // phone looks exactly like the tap-accuracy complaint this all came from,
  // not like a layout bug. So aim taps at real board coordinates and insist
  // the reported cell is the one under the finger.
  group('gutters', () {
    const all = FretboardLabels();

    testWidgets('portrait: a tap still lands on the cell under it',
        (tester) async {
      final cells = <FretPosition>[];
      await pump(tester, labels: all, onCellDown: cells.add);

      // Letters take 18 off the top, numbers 20 off the left.
      const originX = 20.0, originY = 18.0;
      final cellW = (kWidth - originX) / 6;
      final cellH = (kHeight - originY) / 5;
      Offset at(int slot, int row) => Offset(
            originX + (slot + 0.5) * cellW,
            originY + (row + 0.5) * cellH,
          );

      await tester.tapAt(at(2, 3)); // D string, fret 3
      await tester.tapAt(at(0, 0)); // low E open — the corner most at risk
      await tester.tapAt(at(5, 4)); // high E, fret 4
      await tester.pump();

      expect(cells, const [
        FretPosition(2, 3),
        FretPosition(0, 0),
        FretPosition(5, 4),
      ]);
    });

    testWidgets('landscape: the strings are still where the letters say',
        (tester) async {
      final cells = <FretPosition>[];
      await pump(
        tester,
        labels: all,
        orientation: FretboardOrientation.horizontalNeck,
        onCellDown: cells.add,
      );

      // Letters take 18 off the left, numbers 20 off the bottom. Frets are
      // spaced by the scale-length rule here, so only the string axis is
      // aimed at; every tap sits well inside the board along the neck.
      const originX = 18.0;
      final stringPitch = (kHeight - 20.0) / 6;
      final along = originX + (kWidth - originX) / 2;

      // Slot 0 is the top of the neck, and landscape hangs the low E at the
      // bottom — so slot 0 is string 5 and the last slot is string 0.
      await tester.tapAt(Offset(along, 0.5 * stringPitch));
      await tester.tapAt(Offset(along, 5.5 * stringPitch));
      await tester.pump();

      expect(cells.map((c) => c.string), [5, 0]);
    });

    testWidgets('left-handed mirrors the letters with the board',
        (tester) async {
      final cells = <FretPosition>[];
      await pump(tester, labels: all, leftHanded: true, onCellDown: cells.add);

      final cellW = (kWidth - 20.0) / 6;
      await tester.tapAt(Offset(20.0 + 0.5 * cellW, 18.0 + 0.5 * (kHeight - 18) / 5));
      await tester.pump();

      // Left-handed portrait puts the high E in slot 0, so the leftmost
      // column is string 5, not string 0.
      expect(cells.single.string, 5);
    });

    testWidgets('turning them off restores the full-bleed board',
        (tester) async {
      final cells = <FretPosition>[];
      await pump(tester, labels: FretboardLabels.none, onCellDown: cells.add);
      await tester.tapAt(const Offset(0.5 * kCell, 0.5 * kCell));
      await tester.pump();
      expect(cells, const [FretPosition(0, 0)]);
    });
  });
}
