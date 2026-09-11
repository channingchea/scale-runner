// Mode guides: the data, the per-mode seen flag, the demo loop, and the sheet.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scale_runner/onboarding/mode_guides.dart';
import 'package:scale_runner/quiz/quiz_settings.dart';
import 'package:scale_runner/theme/app_theme.dart';
import 'package:scale_runner/theory/fretboard.dart';
import 'package:scale_runner/widgets/guide_demo.dart';
import 'package:scale_runner/widgets/mode_guide_sheet.dart';
import 'package:scale_runner/widgets/piano_keyboard.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  group('modeGuides data', () {
    test('every mode has a guide with 3–4 lines and a non-empty demo', () {
      for (final mode in GuideMode.values) {
        final g = modeGuides[mode];
        expect(g, isNotNull, reason: '$mode');
        expect(g!.lines.length, inInclusiveRange(3, 4), reason: '$mode');
        expect(g.demo, isNotEmpty, reason: '$mode');
      }
    });

    test('demo notes stay inside the piano span (C4..C6)', () {
      final top = GuideDemo.lowMidi + (GuideDemo.octaves * 12).round();
      for (final g in modeGuides.values) {
        for (final f in g.demo) {
          for (final n in {...f.lit, ...f.hints}) {
            expect(
              n,
              inInclusiveRange(GuideDemo.lowMidi, top),
              reason: g.title,
            );
          }
        }
      }
    });

    test('prefs keys are unique per mode', () {
      final keys = GuideMode.values.map((m) => m.prefsKey).toSet();
      expect(keys.length, GuideMode.values.length);
    });
  });

  group('QuizSettings.guideSeen', () {
    test('defaults false and flips per mode', () async {
      final s = await QuizSettings.load();
      expect(await s.guideSeen(GuideMode.scales), isFalse);
      await s.setGuideSeen(GuideMode.scales);
      expect(await s.guideSeen(GuideMode.scales), isTrue);
      expect(
        await s.guideSeen(GuideMode.chords),
        isFalse,
        reason: 'independent of other modes',
      );
      expect(
        await s.introSeen(),
        isFalse,
        reason: 'independent of the app welcome',
      );
    });
  });

  group('GuideDemo', () {
    const frames = [
      DemoFrame({60}, hold: Duration(milliseconds: 300), caption: 'one'),
      DemoFrame({64}, hold: Duration(milliseconds: 300)),
      DemoFrame({67}, hold: Duration(milliseconds: 300), caption: 'three'),
    ];

    Future<void> pumpDemo(WidgetTester tester) => tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        home: const Scaffold(
          body: GuideDemo(frames: frames, instrument: Instrument.piano),
        ),
      ),
    );

    PianoKeyboard keyboard(WidgetTester tester) =>
        tester.widget<PianoKeyboard>(find.byType(PianoKeyboard));

    testWidgets('lights the current frame and advances after its hold', (
      tester,
    ) async {
      await pumpDemo(tester);
      expect(keyboard(tester).isTargetHint(60), isTrue);
      expect(keyboard(tester).isTargetHint(64), isFalse);
      expect(find.text('one'), findsOneWidget);

      // Pump exactly one hold per step so the fake clock stays on the
      // frame boundaries; the caption fade overlaps the next hold.
      await tester.pump(const Duration(milliseconds: 300));
      expect(keyboard(tester).isTargetHint(64), isTrue);
      expect(keyboard(tester).isTargetHint(60), isFalse);
      expect(
        find.text('one'),
        findsOneWidget,
        reason: 'a captionless frame keeps the last caption',
      );

      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('three'), findsOneWidget);

      // Loops back to the first frame.
      await tester.pump(const Duration(milliseconds: 300));
      expect(keyboard(tester).isTargetHint(60), isTrue);
      expect(find.text('one'), findsOneWidget);
    });

    testWidgets('cancels its timer on dispose', (tester) async {
      await pumpDemo(tester);
      await tester.pumpWidget(const SizedBox());
      // A live timer here would fail the test with "A Timer is still
      // pending" at teardown; reaching the end cleanly is the assertion.
    });
  });

  group('ModeGuideSheet', () {
    testWidgets('renders title, every line and the demo; Got it dismisses', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () =>
                    ModeGuideSheet.show(context, GuideMode.scaleRunning),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      final guide = modeGuides[GuideMode.scaleRunning]!;
      expect(find.text(guide.title), findsOneWidget);
      for (final line in guide.lines) {
        expect(find.text(line), findsOneWidget);
      }
      expect(find.byType(GuideDemo), findsOneWidget);

      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
      expect(find.byType(ModeGuideSheet), findsNothing);
    });
  });

  group('maybeShowGuide', () {
    Widget host(GuideMode mode) => MaterialApp(
      theme: AppTheme.dark,
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => maybeShowGuide(context, mode),
            child: const Text('enter'),
          ),
        ),
      ),
    );

    testWidgets('shows once, then never again on this device', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(GuideMode.chords));

      await tester.tap(find.text('enter'));
      await tester.pumpAndSettle();
      expect(find.byType(ModeGuideSheet), findsOneWidget);
      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('enter'));
      await tester.pumpAndSettle();
      expect(find.byType(ModeGuideSheet), findsNothing);
    });
  });
}
