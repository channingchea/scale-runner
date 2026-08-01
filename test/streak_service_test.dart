import 'package:clock/clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:scale_runner/quiz/quiz_settings.dart';
import 'package:scale_runner/streak/streak_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late QuizSettings settings;
  bool isPro = false;

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    settings = await QuizSettings.load();
    isPro = false;
  });

  StreakService freshService() =>
      StreakService(settings: settings, isPro: () => isPro);

  /// Runs [body] with the wall clock pinned to [when].
  Future<T> at<T>(DateTime when, Future<T> Function() body) =>
      withClock(Clock.fixed(when), body);

  final day1 = DateTime(2026, 7, 10, 18); // Friday evening
  DateTime plusDays(int d) => day1.add(Duration(days: d));

  group('recordPractice', () {
    test('first ever practice starts a 1-day streak', () async {
      final s = freshService();
      await at(day1, () async {
        final update = await s.recordPractice();
        expect(update.isFirstToday, isTrue);
        expect(update.milestone, isNull);
        expect(s.currentStreak, 1);
        expect(s.bestStreak, 1);
        expect(s.totalPracticeDays, 1);
        expect(s.practicedToday, isTrue);
      });
    });

    test('second practice same day is a no-op', () async {
      final s = freshService();
      await at(day1, s.recordPractice);
      final update = await at(day1.add(const Duration(hours: 2)),
          s.recordPractice);
      expect(update.isFirstToday, isFalse);
      expect(s.currentStreak, 1);
      expect(s.totalPracticeDays, 1);
    });

    test('consecutive days extend the streak', () async {
      final s = freshService();
      await at(day1, s.recordPractice);
      await at(plusDays(1), s.recordPractice);
      expect(s.currentStreak, 2);
      expect(s.bestStreak, 2);
    });

    test('milestones fire at 3 and 7', () async {
      final s = freshService();
      StreakUpdate? last;
      for (var d = 0; d < 7; d++) {
        last = await at(plusDays(d), s.recordPractice);
        if (d == 2) expect(last!.milestone, 3);
        if (d >= 3 && d < 6) expect(last!.milestone, isNull);
      }
      expect(last!.milestone, 7);
    });

    test('state survives a service reload', () async {
      await at(day1, freshService().recordPractice);
      final s2 = freshService();
      await at(day1, () async {
        await s2.init();
        expect(s2.currentStreak, 1);
        expect(s2.practicedToday, isTrue);
      });
    });
  });

  group('missed days (free user)', () {
    test('one missed day breaks the streak and surfaces StreakLost', () async {
      final s = freshService();
      await at(day1, s.recordPractice);
      await at(plusDays(1), s.recordPractice);
      final s2 = freshService();
      await at(plusDays(3), s2.init); // skipped day 2
      expect(s2.currentStreak, 0);
      expect(s2.bestStreak, 2, reason: 'best is kept');
      final event = s2.consumeOpenEvent();
      expect(event, isA<StreakLost>());
      expect((event as StreakLost).lostStreak, 2);
      expect(s2.consumeOpenEvent(), isNull, reason: 'consumed once');
      // Practicing again starts over at 1.
      await at(plusDays(3), s2.recordPractice);
      expect(s2.currentStreak, 1);
    });
  });

  group('Pro streak freeze', () {
    test('first missed day of the week is auto-repaired', () async {
      isPro = true;
      final s = freshService();
      await at(day1, s.recordPractice);
      await at(plusDays(1), s.recordPractice); // streak 2
      final s2 = freshService();
      await at(plusDays(3), s2.init); // skipped day 2 → freeze
      expect(s2.currentStreak, 2);
      expect(s2.consumeOpenEvent(), isA<StreakFrozen>());
      // Today's practice extends normally.
      await at(plusDays(3), s2.recordPractice);
      expect(s2.currentStreak, 3);
    });

    test('second miss in the same ISO week is not repaired', () async {
      isPro = true;
      // day1 = Fri 2026-07-10. Practice Mon 7/13 + Tue 7/14, miss Wed, freeze
      // Thu; then miss Fri, open Sat — same ISO week → lost.
      final mon = DateTime(2026, 7, 13, 18);
      final s = freshService();
      await at(mon, s.recordPractice);
      await at(mon.add(const Duration(days: 1)), s.recordPractice); // Tue
      await at(mon.add(const Duration(days: 3)), s.init); // Thu: freeze used
      expect(s.currentStreak, 2);
      await at(mon.add(const Duration(days: 3)), s.recordPractice); // Thu = 3
      await at(mon.add(const Duration(days: 5)), s.init); // Sat, missed Fri
      expect(s.currentStreak, 0);
      expect(s.consumeOpenEvent(), isA<StreakLost>());
    });

    test('freeze does not cover a 2+ day gap', () async {
      isPro = true;
      final s = freshService();
      await at(day1, s.recordPractice);
      await at(plusDays(1), s.recordPractice);
      await at(plusDays(4), s.init); // missed 2 days
      expect(s.currentStreak, 0);
      expect(s.consumeOpenEvent(), isA<StreakLost>());
    });
  });

  group('clock edge cases', () {
    test('clock moving backwards never breaks the streak', () async {
      final s = freshService();
      await at(plusDays(1), s.recordPractice);
      await at(day1, s.init); // device clock rolled back a day
      expect(s.currentStreak, 1);
      expect(s.consumeOpenEvent(), isNull);
    });

    test('repeated init on the same day is stable', () async {
      final s = freshService();
      await at(day1, s.recordPractice);
      await at(day1, s.init);
      await at(day1, s.init);
      expect(s.currentStreak, 1);
      expect(s.consumeOpenEvent(), isNull);
    });
  });
}
