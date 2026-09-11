// Home screen layout: modes are grouped into Practice and Drills sections.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scale_runner/main.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  Future<void> pumpHome(WidgetTester tester) async {
    // A tall viewport so every card is laid out without scrolling.
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const ScaleRunnerApp());
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();
    // The first-run welcome sheet covers the home screen; dismiss it.
    if (find.text('Welcome to Scale Runner').evaluate().isNotEmpty) {
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
    }
  }

  double topOf(WidgetTester tester, String text) =>
      tester.getTopLeft(find.text(text)).dy;

  testWidgets('shows Practice and Drills section headers', (tester) async {
    await pumpHome(tester);
    expect(find.text('Practice'), findsOneWidget);
    expect(find.text('Drills'), findsOneWidget);
    expect(find.text('Timed exercises against the metronome'), findsOneWidget);
  });

  testWidgets('Practice modes sit above Drills, drill modes below it', (
    tester,
  ) async {
    await pumpHome(tester);
    final practice = topOf(tester, 'Practice');
    final drills = topOf(tester, 'Drills');
    expect(practice, lessThan(drills));

    for (final mode in ['Free Play', 'Scales', 'Chords', 'Voicings']) {
      final y = topOf(tester, mode);
      expect(y, greaterThan(practice), reason: '$mode below Practice');
      expect(y, lessThan(drills), reason: '$mode above Drills');
    }
    for (final mode in ['Scale Running', 'Inversion Running', 'Jam Mode']) {
      expect(
        topOf(tester, mode),
        greaterThan(drills),
        reason: '$mode below Drills',
      );
    }
  });
}
