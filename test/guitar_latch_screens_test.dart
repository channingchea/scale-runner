import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:scale_runner/midi/midi_service.dart';
import 'package:scale_runner/quiz/quiz_controller.dart' show KeyFeedback, QuizMode;
import 'package:scale_runner/quiz/quiz_settings.dart';
import 'package:scale_runner/screens/free_play_screen.dart';
import 'package:scale_runner/screens/inversion_run_screen.dart';
import 'package:scale_runner/screens/quiz_screen.dart';
import 'package:scale_runner/screens/voicing_drill_screen.dart';
import 'package:scale_runner/theory/fretboard.dart' show Instrument;
import 'package:scale_runner/widgets/fretboard_view.dart' show FretboardView;
import 'package:scale_runner/widgets/instrument_surface.dart';

import 'helpers/guides_seen.dart';

/// Arpeggiated Notes on the fretboard: a tapped cell has to stay sounding
/// after the finger lifts, in every mode that offers the latch. Checked
/// through [InstrumentSurface.feedbackFor], which is what actually paints the
/// board — a screen can hold the right cells and still light nothing.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance = prefsWithGuidesSeen();
    final settings = await QuizSettings.load();
    await settings.setInstrument(Instrument.guitar);
  });

  Future<void> pump(WidgetTester tester, Widget screen) async {
    // Tall on purpose: the guitar board claims 0.62 of the height.
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: screen));
    await tester.pumpAndSettle();
  }

  /// Every note the surface is currently painting as held.
  Set<int> pressed(WidgetTester tester) {
    final s = tester.widget<InstrumentSurface>(find.byType(InstrumentSurface));
    return {
      for (var m = 21; m < 109; m++)
        if (s.feedbackFor(m) == KeyFeedback.pressed) m,
    };
  }

  /// Every note the surface is painting at all. The quiz colours a chord tone
  /// green rather than "held" the moment it lands, so "is anything lit" is the
  /// question there, not "is anything pressed".
  Set<int> lit(WidgetTester tester) {
    final s = tester.widget<InstrumentSurface>(find.byType(InstrumentSurface));
    return {
      for (var m = 21; m < 109; m++)
        if (s.feedbackFor(m) != KeyFeedback.idle) m,
    };
  }

  /// The first cell on the neck sounding [name], e.g. 'C3'.
  Finder cellNamed(String name) => find
      .descendant(
        of: find.byType(FretboardView),
        matching: find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.label == name),
      )
      .first;

  /// Tap the first playable cell on the neck (a Semantics node labelled with
  /// a note name) and let go, the way a finger does.
  Future<void> tapACell(WidgetTester tester) async {
    final cell = find
        .descendant(
          of: find.byType(FretboardView),
          matching: find.byWidgetPredicate((w) =>
              w is Semantics &&
              w.properties.label != null &&
              RegExp(r'^[A-G]#?\d$').hasMatch(w.properties.label!)),
        )
        .first;
    await tester.tap(cell);
    await tester.pumpAndSettle();
  }

  testWidgets('Chords quiz: a chord can be built one fret at a time',
      (tester) async {
    // Pin the prompt to C Major so the frets below are all chord tones.
    final settings = await QuizSettings.load();
    await settings.setEnabledNames(QuizMode.chord, {'Major'});
    await settings.setEnabledRootPcs(QuizMode.chord, {0});
    await pump(tester, QuizScreen(mode: QuizMode.chord, midi: MidiService()));
    expect(pressed(tester), isEmpty);

    // One tone per string, inside the opening 0-4 box: C on the A string,
    // E on the low E, G on the open G string.
    for (final name in ['C3', 'E2', 'G3']) {
      await tester.tap(cellNamed(name));
      await tester.pumpAndSettle();
    }
    expect(find.text('Correct! Press any key to continue'), findsOneWidget,
        reason: 'three latched frets should complete the chord');
  });

  testWidgets('Chords quiz: a wrong fret clears the latched shape',
      (tester) async {
    final settings = await QuizSettings.load();
    await settings.setEnabledNames(QuizMode.chord, {'Major'});
    await settings.setEnabledRootPcs(QuizMode.chord, {0});
    await pump(tester, QuizScreen(mode: QuizMode.chord, midi: MidiService()));

    await tester.tap(cellNamed('C3'));
    await tester.pump();
    expect(lit(tester), isNotEmpty);

    await tester.tap(cellNamed('F2')); // low E fret 1: not in C Major
    await tester.pump();
    expect(lit(tester), isNotEmpty, reason: 'the red flash shows first');
    // An explicit duration, not pumpAndSettle: settling stops as soon as no
    // frame is scheduled, which is well before the 450 ms flash timer.
    await tester.pump(const Duration(milliseconds: 500));
    expect(lit(tester), isEmpty,
        reason: 'a wrong fret starts the chord over');
  });

  testWidgets('Inversion Running: a tapped cell stays sounding',
      (tester) async {
    await pump(tester, InversionRunScreen(midi: MidiService()));
    expect(pressed(tester), isEmpty);
    await tapACell(tester);
    expect(pressed(tester), isNotEmpty);
  });

  testWidgets('Voicings drill: a tapped cell stays sounding', (tester) async {
    await pump(tester, VoicingDrillScreen(midi: MidiService()));
    expect(find.byType(FretboardView), findsOneWidget,
        reason: 'the demo shape should be drillable on a neck');
    expect(pressed(tester), isEmpty);
    await tapACell(tester);
    expect(pressed(tester), isNotEmpty);
  });

  testWidgets('Free Play: a tapped cell stays sounding', (tester) async {
    await pump(tester, FreePlayScreen(midi: MidiService()));
    expect(pressed(tester), isEmpty);
    await tapACell(tester);
    expect(pressed(tester), isNotEmpty);
  });
}
