import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:scale_runner/quiz/quiz_controller.dart' show KeyFeedback;
import 'package:scale_runner/theory/fretboard.dart';
import 'package:scale_runner/ui/responsive.dart';
import 'package:scale_runner/widgets/fretboard_view.dart';
import 'package:scale_runner/widgets/instrument_surface.dart';
import 'package:scale_runner/widgets/piano_keyboard.dart';

/// [InstrumentSurface] is the only place that decides which physical surface
/// a drill sees; every screen swap in Phase 4 leans on it staying correct.
/// These tests never touch a real drill — just that the switch picks the
/// right widget and that the fretboard opens a box actually covering the
/// notes it was told define this round.
void main() {
  Widget harness({
    required Instrument instrument,
    List<int> anchor = const [60, 64, 67],
    bool compact = false,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          height: 300,
          child: InstrumentSurface(
            instrument: instrument,
            lowMidi: 48,
            octaves: 2,
            anchor: anchor,
            feedbackFor: (_) => KeyFeedback.idle,
            isTargetHint: (_) => false,
            onKeyDown: (_) {},
            onKeyUp: (_) {},
            compact: compact,
          ),
        ),
      ),
    );
  }

  testWidgets('piano instrument renders PianoKeyboard, not the fretboard',
      (tester) async {
    await tester.pumpWidget(harness(instrument: Instrument.piano));
    expect(find.byType(PianoKeyboard), findsOneWidget);
    expect(find.byType(FretboardView), findsNothing);
  });

  testWidgets('guitar instrument renders FretboardView, not the piano',
      (tester) async {
    await tester.pumpWidget(harness(instrument: Instrument.guitar));
    expect(find.byType(FretboardView), findsOneWidget);
    expect(find.byType(PianoKeyboard), findsNothing);
  });

  testWidgets('guitar box covers every anchor note', (tester) async {
    // A C major triad spread over two octaves — wide enough that a box
    // covering it all is a real constraint, not a given.
    const anchor = [48, 55, 64, 72];
    await tester.pumpWidget(
        harness(instrument: Instrument.guitar, anchor: anchor));
    final view = tester.widget<FretboardView>(find.byType(FretboardView));
    for (final midi in anchor) {
      final reachable = positionsFor(midi, tuning: view.tuning)
          .any((p) => view.box.contains(p.fret));
      expect(reachable, isTrue,
          reason: 'MIDI $midi has no reachable position inside '
              '${view.box.start}-${view.box.end}');
    }
  });

  testWidgets(
      'portrait (not compact) opens the vertical box, except on desktop '
      'which is always the neck', (tester) async {
    await tester
        .pumpWidget(harness(instrument: Instrument.guitar, compact: false));
    final view = tester.widget<FretboardView>(find.byType(FretboardView));
    expect(
        view.orientation,
        isDesktopPlatform
            ? FretboardOrientation.horizontalNeck
            : FretboardOrientation.verticalBox);
  });

  testWidgets('compact (landscape phone) opens the horizontal neck',
      (tester) async {
    await tester
        .pumpWidget(harness(instrument: Instrument.guitar, compact: true));
    final view = tester.widget<FretboardView>(find.byType(FretboardView));
    expect(view.orientation, FretboardOrientation.horizontalNeck);
  });
}
