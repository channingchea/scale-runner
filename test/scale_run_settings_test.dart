import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:scale_runner/quiz/quiz_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late QuizSettings settings;

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    settings = await QuizSettings.load();
  });

  group('Scale Running target dots', () {
    test('default on, matching the other drills', () async {
      expect(await settings.runShowDots(), isTrue);
    });

    test('round-trips off and back on', () async {
      await settings.setRunShowDots(false);
      expect(await settings.runShowDots(), isFalse);
      await settings.setRunShowDots(true);
      expect(await settings.runShowDots(), isTrue);
    });

    test('is its own pref, independent of the other drills', () async {
      await settings.setRunShowDots(false);
      expect(await settings.invShowDots(), isTrue);
      expect(await settings.jamShowDots(), isTrue);
      expect(await settings.voicingShowDots(), isTrue);
    });
  });
}
