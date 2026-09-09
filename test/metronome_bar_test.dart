import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scale_runner/runner/meter.dart';
import 'package:scale_runner/widgets/metronome_bar.dart';

/// The expanded metronome pill: the meter chip picks a time signature and
/// persists it, shows beat dots only when a meter accents, and goes inert
/// while a drill has it locked.
void main() {
  Future<MetronomeController> pump(
    WidgetTester tester, {
    bool locked = false,
    Meter meter = Meter.none,
    ValueChanged<Meter>? onMeterChanged,
  }) async {
    final m = MetronomeController(
      bpm: 100,
      silent: true,
      meter: meter,
      onMeterChanged: onMeterChanged,
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(child: MetronomeBar(controller: m, meterLocked: locked)),
      ),
    ));
    await tester.tap(find.byTooltip('Metronome')); // expand
    await tester.pumpAndSettle();
    return m;
  }

  testWidgets('picking a meter sets it on the controller and persists it',
      (tester) async {
    Meter? saved;
    final m = await pump(tester, onMeterChanged: (x) => saved = x);
    expect(find.byIcon(Icons.music_off), findsOneWidget); // No accent chip
    expect(find.text('100'), findsOneWidget);

    await tester.tap(find.byTooltip('Meter'));
    await tester.pumpAndSettle();
    expect(find.text('3/4'), findsOneWidget);
    expect(find.text('Each click is an eighth note'), findsNWidgets(2));

    await tester.tap(find.text('3/4'));
    await tester.pumpAndSettle();
    expect(m.meter, Meter.threeFour);
    expect(saved, Meter.threeFour);
    expect(find.text('3/4'), findsOneWidget); // now the chip's label
    expect(find.byIcon(Icons.music_off), findsNothing);
    m.dispose();
  });

  testWidgets('a locked chip cannot be opened', (tester) async {
    final m = await pump(tester, locked: true, meter: Meter.fourFour);
    expect(find.text('4/4'), findsOneWidget);
    await tester.tap(find.byTooltip('Meter (locked while running)'));
    await tester.pumpAndSettle();
    expect(find.text('3/4'), findsNothing); // no menu
    expect(m.meter, Meter.fourFour);
    m.dispose();
  });

  testWidgets('beat dots follow the bar and vanish for No accent',
      (tester) async {
    final m = await pump(tester, meter: Meter.threeFour);
    // Three dots under the BPM: circle containers inside the pill.
    Iterable<Container> dots() => tester
        .widgetList<Container>(find.byType(Container))
        .where((c) => (c.decoration as BoxDecoration?)?.shape == BoxShape.circle);
    expect(dots().length, 3);

    m.start();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 650)); // beat 1
    expect(m.beatInBar, 1);
    m.stop();
    await tester.pump();

    m.meter = Meter.none;
    await tester.pump();
    expect(dots(), isEmpty);
    m.dispose();
  });
}
