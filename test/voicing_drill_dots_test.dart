import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:scale_runner/midi/midi_service.dart';
import 'package:scale_runner/quiz/quiz_settings.dart';
import 'package:scale_runner/screens/voicing_drill_screen.dart';
import 'package:scale_runner/theory/fretboard.dart' show Instrument;
import 'package:scale_runner/widgets/instrument_surface.dart';

/// The Target dots switch has to reach the keyboard mid-drill: it is the one
/// setting the player is meant to flip the moment the shape starts to stick,
/// without throwing the run away.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  Future<void> pump(WidgetTester tester) async {
    // A tall viewport on purpose: the guitar board claims 0.62 of the height,
    // which pushes Start off an 800x600 test surface and makes the tap a
    // silent no-op.
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: VoicingDrillScreen(midi: MidiService()),
    ));
    await tester.pumpAndSettle();
  }

  /// Whether the surface is being told to hint ANY note in its range.
  /// Asked of [InstrumentSurface] so it reads the same on piano and guitar.
  bool anyHint(WidgetTester tester) {
    final s = tester.widget<InstrumentSurface>(find.byType(InstrumentSurface));
    for (var m = 21; m < 109; m++) {
      if (s.isTargetHint(m)) return true;
    }
    return false;
  }

  Future<void> toggleTargetDots(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Drill settings'));
    await tester.pumpAndSettle();
    // The sheet's list is a lazy ListView, so the Challenge section is not
    // built until it is scrolled into view.
    await tester.scrollUntilVisible(
      find.text('Target dots'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Target dots'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
  }

  testWidgets('Target dots off clears the hints without stopping the drill',
      (tester) async {
    await pump(tester);
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(anyHint(tester), isTrue, reason: 'dots default on');

    await toggleTargetDots(tester);
    expect(await (await QuizSettings.load()).voicingShowDots(), isFalse,
        reason: 'the switch persisted');
    expect(anyHint(tester), isFalse);
  });

  testWidgets('and does the same on the guitar board', (tester) async {
    await (await QuizSettings.load()).setInstrument(Instrument.guitar);
    await pump(tester);
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(anyHint(tester), isTrue, reason: 'dots default on');

    await toggleTargetDots(tester);
    expect(anyHint(tester), isFalse);
  });

  testWidgets('and turns them back on without restarting', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    await toggleTargetDots(tester);
    expect(anyHint(tester), isFalse);
    await toggleTargetDots(tester);
    expect(anyHint(tester), isTrue);
  });
}
