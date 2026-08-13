// Screenshot harness for App Store listing images.
//
// This is NOT a correctness test — it drives the app to each screen worth
// showing on a store listing and holds it there long enough for an external
// capture to grab it:
//
//   xcrun simctl io booted screenshot shot.png
//
// Why external capture instead of binding.takeScreenshot(): simctl grabs the
// device framebuffer at exact native resolution (2064x2752 on iPad Pro 13"),
// which is what App Store Connect wants, with no scaling step in between.
//
// Run it against a booted simulator:
//   flutter test integration_test/store_screens_test.dart -d <simulator-udid>
//
// Each screen is announced on stdout as `SHOT: <name>` and then held for
// [_hold]. Poll-capture on the outside and pick the frames you want.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:scale_runner/main.dart' as app;

/// How long each screen stays put. Long enough that a 2s external capture
/// loop lands at least two frames on it.
const _hold = Duration(seconds: 12);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('walk the screens worth screenshotting', (tester) async {
    app.main();
    await _pumpFor(tester, const Duration(seconds: 8));

    await _shot(tester, 'home');

    await _openFromHome(tester, 'Scales');
    await _shot(tester, 'scales');
    await _back(tester);

    await _openFromHome(tester, 'Chords');
    await _shot(tester, 'chords');
    await _back(tester);

    await _openFromHome(tester, 'Voicings');
    await _shot(tester, 'voicings');
    await _back(tester);

    await _tapIcon(tester, Icons.bar_chart_outlined);
    await _shot(tester, 'stats');
    await _back(tester);

    await _tapIcon(tester, Icons.settings_outlined);
    await _shot(tester, 'settings');
    await _back(tester);
  });
}

/// pumpAndSettle is unsafe here — the app has looping animations (the flashing
/// Calibrate affordance, splash) that never settle. Pump fixed frames instead.
Future<void> _pumpFor(WidgetTester tester, Duration total) async {
  final end = DateTime.now().add(total);
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _shot(WidgetTester tester, String name) async {
  // ignore: avoid_print
  print('SHOT: $name');
  await _pumpFor(tester, _hold);
}

Future<void> _openFromHome(WidgetTester tester, String title) async {
  final target = find.text(title);
  if (target.evaluate().isEmpty) {
    // ignore: avoid_print
    print('SKIP: $title not found on home');
    return;
  }
  await tester.tap(target.first);
  await _pumpFor(tester, const Duration(seconds: 3));
}

Future<void> _tapIcon(WidgetTester tester, IconData icon) async {
  final target = find.byIcon(icon);
  if (target.evaluate().isEmpty) {
    // ignore: avoid_print
    print('SKIP: icon not found');
    return;
  }
  await tester.tap(target.first);
  await _pumpFor(tester, const Duration(seconds: 3));
}

/// Pops whatever is on top, tolerating screens that dismiss themselves.
Future<void> _back(WidgetTester tester) async {
  final backButton = find.byType(BackButton);
  if (backButton.evaluate().isNotEmpty) {
    await tester.tap(backButton.first);
  } else {
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    if (nav.canPop()) nav.pop();
  }
  await _pumpFor(tester, const Duration(seconds: 3));
}
