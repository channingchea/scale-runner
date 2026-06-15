// Smoke test: the app builds and shows the home screen.

import 'package:flutter_test/flutter_test.dart';
import 'package:scale_runner/main.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
  });

  testWidgets('app launches to home screen', (tester) async {
    await tester.pumpWidget(const ScaleRunnerApp());
    // Wait for the splash screen duration (1100ms) + switcher transition duration (350ms)
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();

    expect(find.text('Scale Runner'), findsOneWidget);
    expect(find.text('Scales'), findsOneWidget);
    expect(find.text('Chords'), findsOneWidget);
  });
}
