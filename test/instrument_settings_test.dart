import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:scale_runner/quiz/quiz_settings.dart';
import 'package:scale_runner/theory/fretboard.dart';
import 'package:scale_runner/widgets/fretboard_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late QuizSettings settings;

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    settings = await QuizSettings.load();
  });

  group('Instrument', () {
    test('defaults to piano', () async {
      expect(await settings.instrument(), Instrument.piano);
    });

    test('round-trips to guitar and back', () async {
      await settings.setInstrument(Instrument.guitar);
      expect(await settings.instrument(), Instrument.guitar);
      await settings.setInstrument(Instrument.piano);
      expect(await settings.instrument(), Instrument.piano);
    });
  });

  group('Left-handed', () {
    test('defaults off', () async {
      expect(await settings.leftHanded(), isFalse);
    });

    test('round-trips on and back off', () async {
      await settings.setLeftHanded(true);
      expect(await settings.leftHanded(), isTrue);
      await settings.setLeftHanded(false);
      expect(await settings.leftHanded(), isFalse);
    });
  });

  group('Guitar twin-dot mode', () {
    test('defaults to primary + ghost', () async {
      expect(await settings.guitarTwinMode(), TwinDotMode.primaryAndGhost);
    });

    test('round-trips through every mode', () async {
      for (final mode in TwinDotMode.values) {
        await settings.setGuitarTwinMode(mode);
        expect(await settings.guitarTwinMode(), mode);
      }
    });
  });
}
