import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:scale_runner/midi/midi_service.dart';
import 'package:scale_runner/quiz/quiz_settings.dart';
import 'package:scale_runner/screens/voicing_capture_screen.dart';
import 'package:scale_runner/theory/fretboard.dart';
import 'package:scale_runner/widgets/fretboard_view.dart' show FretboardView;

/// Capture is the one screen where the guitar is not merely a different
/// picture of the same model: the shape is cells, not pitches, because a note
/// inside a five-fret box can sit on two strings and only the tap knows which.
///
/// Cells are aimed at through the per-cell semantics nodes rather than by
/// coordinate. The board is centred inside its widget at a capped size and
/// lies flat as a neck on desktop, so a hand-computed offset would be testing
/// the layout maths instead of the behaviour.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final settings = await QuizSettings.load();
    await settings.setInstrument(Instrument.guitar);
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: VoicingCaptureScreen(midi: MidiService()),
    ));
    await tester.pumpAndSettle();
  }

  /// The cell whose note is [name]. Frets 0-4 hold one duplicate pair — B3 is
  /// both the G string at fret 4 and the open B string — and the cells are
  /// built string by string, so `.first` is the lower string of the pair.
  Finder cell(String name) => find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == name,
      );

  /// Note names of frets 1 and 4 on each of the six strings, in string order.
  const fret1 = ['F2', 'A#2', 'D#3', 'G#3', 'C4', 'F4'];
  const fret4 = ['G#2', 'C#3', 'F#3', 'B3', 'D#4', 'G#4'];

  testWidgets('the window opens at the nut and slides a fret at a time',
      (tester) async {
    await pump(tester);
    // Tests run on macOS, where isDesktopPlatform forces the horizontal neck,
    // so this is the vertical stepper down the left edge. Its readout drops
    // the word "Frets" because it has 46 points to fit in — see
    // _buildBoxStepper. The portrait row still reads "Frets 0-4".
    expect(find.text('0-4'), findsOneWidget);

    // Already at the nut, so there is nowhere lower to go.
    final toNut = tester.widget<IconButton>(find
        .ancestor(
          of: find.byTooltip('Toward the nut'),
          matching: find.byType(IconButton),
        )
        .first);
    expect(toNut.onPressed, isNull);

    await tester.tap(find.byTooltip('Up the neck'));
    await tester.pumpAndSettle();
    expect(find.text('1-5'), findsOneWidget);
  });

  testWidgets('the stepper stands beside the neck, not above it',
      (tester) async {
    await pump(tester);
    // The whole point of the landscape layout: the control must not eat into
    // the board's height. Its left edge sits at or before the board's, and
    // the two do not overlap vertically-stacked.
    final stepper = tester.getRect(find
        .ancestor(
          of: find.byTooltip('Up the neck'),
          matching: find.byType(IconButton),
        )
        .first);
    final board = tester.getRect(find.byType(FretboardView));
    expect(stepper.right, lessThanOrEqualTo(board.left + 1),
        reason: 'stepper should be to the left of the board');
    expect(stepper.center.dy, greaterThan(board.top),
        reason: 'stepper should sit alongside the board, not above it');
  });

  testWidgets('a tap latches the note on the string it was tapped on',
      (tester) async {
    await pump(tester);
    expect(find.text('No notes yet.'), findsOneWidget);

    await tester.tap(cell('E2').first); // low E, open
    await tester.pumpAndSettle();
    expect(find.text('E2'), findsOneWidget);
  });

  testWidgets("a second tap on a string moves that string's note",
      (tester) async {
    await pump(tester);
    await tester.tap(cell('E2').first); // low E, fret 0
    await tester.pumpAndSettle();
    await tester.tap(cell('G#2').first); // low E, fret 4
    await tester.pumpAndSettle();

    // Moved, not stacked. One string holds one note, which is what makes a
    // captured guitar shape playable by construction.
    expect(find.text('E2'), findsNothing);
    expect(find.text('G#2'), findsOneWidget);
  });

  testWidgets('tapping a lit cell takes the note off again', (tester) async {
    await pump(tester);
    await tester.tap(cell('E4').first); // high E, open
    await tester.pumpAndSettle();
    expect(find.text('No notes yet.'), findsNothing);

    await tester.tap(cell('E4').first);
    await tester.pumpAndSettle();
    expect(find.text('No notes yet.'), findsOneWidget);
  });

  testWidgets('twelve taps across six strings leave six notes',
      (tester) async {
    await pump(tester);
    for (final name in fret1) {
      await tester.tap(cell(name).first);
      await tester.pumpAndSettle();
    }
    for (final name in fret4) {
      await tester.tap(cell(name).first);
      await tester.pumpAndSettle();
    }

    for (final name in fret1) {
      expect(find.text(name), findsNothing, reason: '$name should have moved');
    }
    for (final name in fret4) {
      expect(find.text(name), findsOneWidget, reason: 'missing $name');
    }
  });
}
