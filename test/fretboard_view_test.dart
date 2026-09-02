import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scale_runner/quiz/quiz_controller.dart' show KeyFeedback;
import 'package:scale_runner/theory/fretboard.dart';
import 'package:scale_runner/widgets/fretboard_view.dart';

/// The board is pinned to 300 x 250 at the top left, so a cell is exactly
/// 50 x 50 and a tap can be aimed at a named string and fret.
const double kCell = 50;

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
    KeyFeedback Function(int)? feedbackFor,
    bool Function(int)? isTargetHint,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 300,
          height: 250,
          child: FretboardView(
            box: box,
            orientation: orientation,
            leftHanded: leftHanded,
            twinMode: twinMode,
            feedbackFor: feedbackFor ?? (_) => KeyFeedback.idle,
            isTargetHint: isTargetHint ?? (_) => false,
            onKeyDown: down.add,
            onKeyUp: up.add,
          ),
        ),
      ),
    ));
  }

  /// Centre of the cell drawn in string slot [slot] and fret row [row].
  Offset cell(int slot, int row) =>
      Offset((slot + 0.5) * kCell, (row + 0.5) * kCell);

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
}
