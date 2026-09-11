// Mode guides on the real screens: auto-show on first entry, silent after,
// and the "?" button replays them.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scale_runner/midi/midi_service.dart';
import 'package:scale_runner/onboarding/mode_guides.dart';
import 'package:scale_runner/quiz/quiz_controller.dart';
import 'package:scale_runner/screens/free_play_screen.dart';
import 'package:scale_runner/screens/quiz_screen.dart';
import 'package:scale_runner/screens/scale_run_screen.dart';
import 'package:scale_runner/theme/app_theme.dart';
import 'package:scale_runner/widgets/mode_guide_sheet.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'helpers/guides_seen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pump(WidgetTester tester, Widget screen) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: AppTheme.dark, home: screen));
    await tester.pumpAndSettle();
  }

  final screens = <String, (Widget, GuideMode)>{
    'Free Play': (FreePlayScreen(midi: MidiService()), GuideMode.freePlay),
    'Scales': (
      QuizScreen(mode: QuizMode.scale, midi: MidiService()),
      GuideMode.scales,
    ),
    'Scale Running': (
      ScaleRunScreen(midi: MidiService()),
      GuideMode.scaleRunning,
    ),
  };

  for (final entry in screens.entries) {
    final (screen, mode) = entry.value;
    final title = modeGuides[mode]!.title;

    testWidgets('${entry.key}: guide auto-shows on a fresh device', (
      tester,
    ) async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.empty();
      await pump(tester, screen);
      expect(find.byType(ModeGuideSheet), findsOneWidget);
      expect(find.text(title), findsWidgets);
      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
      expect(find.byType(ModeGuideSheet), findsNothing);
    });

    testWidgets('${entry.key}: stays quiet once seen, "?" replays it', (
      tester,
    ) async {
      SharedPreferencesAsyncPlatform.instance = prefsWithGuidesSeen();
      await pump(tester, screen);
      expect(find.byType(ModeGuideSheet), findsNothing);

      await tester.tap(find.byTooltip('$title guide'));
      await tester.pumpAndSettle();
      expect(find.byType(ModeGuideSheet), findsOneWidget);
    });
  }
}
