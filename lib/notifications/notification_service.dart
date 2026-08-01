import 'dart:io' show Platform;

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../quiz/quiz_settings.dart';
import '../streak/streak_service.dart';

/// Local practice-reminder notifications. No backend: everything is scheduled
/// on-device and re-evaluated on every app open / recorded practice, because
/// a scheduled notification can't check conditions at fire time.
///
/// Three slots (stable ids, rescheduling replaces in place):
///  1. daily reminder at the user's chosen time (repeats daily)
///  2. streak-at-risk nudge at 20:30, only armed when a streak ≥2 would
///     break tonight
///  3. win-back, 4 days after the last practice/app-open
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const int _dailyId = 1;
  static const int _atRiskId = 2;
  static const int _winBackId = 3;

  static const _atRiskHour = 20, _atRiskMinute = 30;
  static const _winBackDays = 4;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _inited = false;

  bool get _supported => !kIsWeb && (Platform.isIOS || Platform.isAndroid);

  Future<void> init() async {
    if (_inited || !_supported) return;
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (e) {
      debugPrint('NotificationService: timezone lookup failed: $e');
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          // Permission is requested explicitly via requestPermission(), at a
          // moment the user has context — not at first plugin init.
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _inited = true;
  }

  /// Shows the OS permission dialog. Returns whether we can post.
  Future<bool> requestPermission() async {
    if (!_supported) return false;
    await init();
    if (Platform.isIOS) {
      final ios = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();
      return await ios?.requestPermissions(
              alert: true, badge: true, sound: true) ??
          false;
    }
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? false;
  }

  /// Re-evaluates and (re)schedules all three slots from current state.
  /// Called on app start, on resume, after every recorded practice, and when
  /// reminder settings change. Safe to call often.
  Future<void> resync() async {
    if (!_supported) return;
    try {
      await init();
      final settings = await QuizSettings.load();
      if (!await settings.remindersEnabled()) {
        await _plugin.cancelAll();
        return;
      }
      final streak = StreakService.instance;
      await streak.init();
      final (hour, minute) = await settings.reminderTime();
      await _scheduleDaily(hour, minute, skipToday: streak.practicedToday);
      await _scheduleAtRisk(streak);
      await _scheduleWinBack(hour, minute, streak.currentStreak);
    } catch (e) {
      // Never let notification plumbing break app startup or session end.
      debugPrint('NotificationService.resync failed: $e');
    }
  }

  Future<void> cancelAll() async {
    if (!_supported || !_inited) return;
    await _plugin.cancelAll();
  }

  /// Daily repeating reminder. When today's practice is already done (or
  /// today's time has passed), the series starts tomorrow — future days stay
  /// covered even if the app isn't opened again.
  Future<void> _scheduleDaily(int hour, int minute,
      {required bool skipToday}) async {
    var when = _nextInstanceOf(hour, minute);
    if (skipToday && _isToday(when)) {
      when = when.add(const Duration(days: 1));
    }
    await _plugin.zonedSchedule(
      id: _dailyId,
      title: 'Time to practice 🎹',
      body: 'A few minutes at the keys keeps you moving forward.',
      scheduledDate: when,
      notificationDetails: _details(),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time, // repeat daily
    );
  }

  /// One-shot evening nudge, armed only when a streak ≥2 would break tonight.
  Future<void> _scheduleAtRisk(StreakService streak) async {
    final arm = streak.currentStreak >= 2 && !streak.practicedToday;
    final when = _todayAt(_atRiskHour, _atRiskMinute);
    if (!arm || !when.isAfter(tz.TZDateTime.from(clock.now(), tz.local))) {
      await _plugin.cancel(id: _atRiskId);
      return;
    }
    await _plugin.zonedSchedule(
      id: _atRiskId,
      title: '🔥 ${streak.currentStreak}-day streak on the line',
      body: 'It ends at midnight — one quick session saves it.',
      scheduledDate: when,
      notificationDetails: _details(),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  /// One-shot win-back, pushed out again on every resync (app open or
  /// practice), so it only ever fires after [_winBackDays] of real inactivity.
  Future<void> _scheduleWinBack(int hour, int minute, int streak) async {
    await _plugin.zonedSchedule(
      id: _winBackId,
      title: 'Your scales miss you 🎹',
      body: streak >= 2
          ? 'You built a $streak-day streak once — five minutes starts the next one.'
          : 'Pick up where you left off — five minutes counts.',
      scheduledDate:
          _nextInstanceOf(hour, minute).add(const Duration(days: _winBackDays)),
      notificationDetails: _details(),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  NotificationDetails _details() => const NotificationDetails(
        android: AndroidNotificationDetails(
          'practice_reminders',
          'Practice reminders',
          channelDescription:
              'Daily practice reminders and streak alerts',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
      );

  tz.TZDateTime _todayAt(int hour, int minute) {
    final now = tz.TZDateTime.from(clock.now(), tz.local);
    return tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
  }

  tz.TZDateTime _nextInstanceOf(int hour, int minute) {
    final now = tz.TZDateTime.from(clock.now(), tz.local);
    var when = _todayAt(hour, minute);
    if (!when.isAfter(now)) when = when.add(const Duration(days: 1));
    return when;
  }

  bool _isToday(tz.TZDateTime when) {
    final now = tz.TZDateTime.from(clock.now(), tz.local);
    return when.year == now.year &&
        when.month == now.month &&
        when.day == now.day;
  }
}
