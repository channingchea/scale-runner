import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:scale_runner/quiz/quiz_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const mode = QuizSettings.modeScaleRun;
  late QuizSettings settings;

  Future<void> boot([Map<String, Object> initial = const {}]) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData(initial);
    settings = await QuizSettings.load();
  }

  setUp(() => boot());

  test('a fresh install gets three free sessions', () async {
    expect(QuizSettings.freeTrialSessions, 3);
    expect(await settings.trialsUsed(mode), 0);
    expect(await settings.trialsRemaining(mode), 3);
  });

  test('each consumed session decrements, then sticks at zero', () async {
    expect(await settings.consumeTrial(mode), 2);
    expect(await settings.consumeTrial(mode), 1);
    expect(await settings.consumeTrial(mode), 0);
    expect(await settings.consumeTrial(mode), 0);
    expect(await settings.trialsRemaining(mode), 0);
  });

  test('modes track their trials independently', () async {
    await settings.consumeTrial(mode);
    expect(await settings.trialsRemaining(QuizSettings.modeJam), 3);
    expect(await settings.trialsRemaining(QuizSettings.modeInversionRun), 3);
  });

  test('an old one-shot trial counts as one used, not three', () async {
    await boot({'trial_used_$mode': true});
    expect(await settings.trialsUsed(mode), 1);
    expect(await settings.trialsRemaining(mode), 2);
  });

  test('an unspent old trial migrates to the full three', () async {
    await boot({'trial_used_$mode': false});
    expect(await settings.trialsRemaining(mode), 3);
  });

  test('the new counter wins over a stale legacy flag', () async {
    await boot({'trial_used_$mode': true, 'trial_count_$mode': 3});
    expect(await settings.trialsRemaining(mode), 0);
  });
}
