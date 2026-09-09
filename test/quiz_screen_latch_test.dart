import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:scale_runner/midi/midi_service.dart';
import 'package:scale_runner/quiz/quiz_controller.dart' show QuizMode;
import 'package:scale_runner/quiz/quiz_settings.dart';
import 'package:scale_runner/screens/quiz_screen.dart';
import 'package:scale_runner/theory/fretboard.dart';
import 'package:scale_runner/widgets/fretboard_view.dart' show FretboardView;

/// The Arpeggiated Notes wiring between the Chords quiz screen and its
/// fretboard: with the setting on, the board runs in cell mode and the
/// screen's cell set is what it lights; with it off, taps are plain presses.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    final settings = await QuizSettings.load();
    await settings.setInstrument(Instrument.guitar);
  });

  Future<void> pump(WidgetTester tester, QuizMode mode) async {
    await tester.pumpWidget(MaterialApp(
      home: QuizScreen(mode: mode, midi: MidiService()),
    ));
    await tester.pumpAndSettle();
  }

  Finder cell(String name) => find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == name,
      );

  FretboardView board(WidgetTester tester) =>
      tester.widget<FretboardView>(find.byType(FretboardView));

  testWidgets('chord quiz on guitar keeps the tapped shape as cells',
      (tester) async {
    // Pin the prompt to C Major so every tap below is a chord tone and no
    // wrong-note flash purges the latch mid-test.
    final settings = await QuizSettings.load();
    await settings.setEnabledNames(QuizMode.chord, {'Major'});
    await settings.setEnabledRootPcs(QuizMode.chord, {0});
    await pump(tester, QuizMode.chord);
    expect(board(tester).onCellDown, isNotNull);
    expect(board(tester).latched, isEmpty);

    await tester.tap(cell('E4').first); // high E string, open
    await tester.pumpAndSettle();
    expect(board(tester).latched, {const FretPosition(5, 0)});

    // A second tap on the same string moves the note; the old cell goes.
    await tester.tap(cell('G4').first); // high E string, fret 3
    await tester.pumpAndSettle();
    expect(board(tester).latched, {const FretPosition(5, 3)});

    // A tap on a lit cell puts it out.
    await tester.tap(cell('G4').first);
    await tester.pumpAndSettle();
    expect(board(tester).latched, isEmpty);
  });

  testWidgets('with the setting off the board takes plain presses',
      (tester) async {
    final settings = await QuizSettings.load();
    await settings.setArpeggiatedNotes(false);
    await pump(tester, QuizMode.chord);
    expect(board(tester).onCellDown, isNull);
    expect(board(tester).latched, isNull);
  });

  testWidgets('the scale quiz never latches, whatever the setting',
      (tester) async {
    await pump(tester, QuizMode.scale);
    expect(board(tester).onCellDown, isNull);
    expect(board(tester).latched, isNull);
  });
}
