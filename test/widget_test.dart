// Smoke test: the app builds and shows the home screen.

import 'package:flutter_test/flutter_test.dart';
import 'package:scale_runner/main.dart';

void main() {
  testWidgets('app launches to home screen', (tester) async {
    await tester.pumpWidget(const ScaleRunnerApp());
    await tester.pump();

    expect(find.text('Scale Runner'), findsOneWidget);
    expect(find.text('Scales'), findsOneWidget);
    expect(find.text('Chords'), findsOneWidget);
  });
}
