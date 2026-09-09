import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:scale_runner/midi/midi_service.dart';
import 'package:scale_runner/quiz/quiz_settings.dart';
import 'package:scale_runner/screens/free_play_screen.dart';
import 'package:scale_runner/theory/fretboard.dart';

/// Keys and cells are aimed at through their semantics labels (note names),
/// the same way the capture tests do, so nothing here depends on layout maths.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: FreePlayScreen(midi: MidiService()),
    ));
    await tester.pumpAndSettle();
  }

  Finder key(String name) => find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == name,
      );

  testWidgets('piano: taps latch by default and the readout names them',
      (tester) async {
    await pump(tester);
    expect(find.text('Play anything'), findsOneWidget);

    await tester.tap(key('C4'));
    await tester.pump();
    expect(find.text('C4'), findsWidgets); // the readout (and the key label)

    await tester.tap(key('E4'));
    await tester.pump();
    expect(find.text('Major 3rd'), findsOneWidget);
    expect(find.text('C4 – E4'), findsOneWidget);

    await tester.tap(key('G4'));
    await tester.pump();
    expect(find.text('C Major'), findsOneWidget);
    expect(find.text('1-3-5'), findsOneWidget);

    // A second tap on a lit key puts it out.
    await tester.tap(key('E4'));
    await tester.pump();
    expect(find.text('Perfect 5th'), findsOneWidget);

    // Two idle seconds and the latch lets go.
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.text('Play anything'), findsOneWidget);
  });

  testWidgets('piano: with Arpeggiated Notes off, lifting the finger clears '
      'the readout', (tester) async {
    final settings = await QuizSettings.load();
    await settings.setArpeggiatedNotes(false);
    await pump(tester);

    final gesture = await tester.startGesture(tester.getCenter(key('D4')));
    await tester.pump();
    expect(find.text('D4'), findsWidgets);
    await gesture.up();
    await tester.pump();
    expect(find.text('Play anything'), findsOneWidget);
  });

  testWidgets('guitar: the board and fret stepper show, naming stays blank',
      (tester) async {
    final settings = await QuizSettings.load();
    await settings.setInstrument(Instrument.guitar);
    await pump(tester);

    expect(find.text('Play anything'), findsOneWidget);
    // Desktop lays the neck flat, so this is the vertical stepper's readout.
    expect(find.text('0-4'), findsOneWidget);

    await tester.tap(find.byTooltip('Up the neck'));
    await tester.pumpAndSettle();
    expect(find.text('1-5'), findsOneWidget);

    // A cell tap lights the cell but names nothing on day one.
    final gesture = await tester.startGesture(tester.getCenter(key('F4').first));
    await tester.pump();
    expect(find.text('Play anything'), findsOneWidget);
    await gesture.up();
    await tester.pump();
  });
}
