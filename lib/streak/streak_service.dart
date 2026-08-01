import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import '../purchases/purchase_service.dart';
import '../quiz/quiz_settings.dart';

/// Result of recording one practice session.
class StreakUpdate {
  const StreakUpdate({required this.isFirstToday, this.milestone});

  /// True when this call extended the streak (first practice of the day).
  final bool isFirstToday;

  /// Set to the streak length (3, 7, 14, 30, 100) when this practice hit a
  /// milestone, null otherwise.
  final int? milestone;
}

/// What happened to the streak when the app was (re)opened.
sealed class StreakOpenEvent {
  const StreakOpenEvent();
}

/// A Pro freeze auto-repaired a single missed day; [streak] survives.
class StreakFrozen extends StreakOpenEvent {
  const StreakFrozen(this.streak);
  final int streak;
}

/// The streak broke. [lostStreak] is what the user had; shown on the
/// recovery sheet ("Pro would have saved it") for free users.
class StreakLost extends StreakOpenEvent {
  const StreakLost(this.lostStreak);
  final int lostStreak;
}

/// Tracks the daily practice streak: one completed session per local calendar
/// day keeps it alive. Distinct from the in-session `streak` (consecutive
/// correct answers) that lives in each mode's controller.
///
/// Freeze rule: for Pro users, the first missed day in an ISO week is
/// auto-repaired on next app open. Free users lose the streak (previous value
/// is surfaced via [StreakLost] as the paywall conversion moment).
class StreakService extends ChangeNotifier {
  StreakService({QuizSettings? settings, bool Function()? isPro})
      : _settings = settings, // ignore: prefer_initializing_formals
        _isPro = isPro ?? (() => PurchaseService.instance.isPro);

  static final StreakService instance = StreakService();

  static const List<int> milestones = [3, 7, 14, 30, 100];

  QuizSettings? _settings;
  final bool Function() _isPro;

  int _current = 0;
  int _best = 0;
  int _totalDays = 0;
  DateTime? _lastDate; // date-only, local
  bool _loaded = false;

  /// Consumed once by the UI after app open (freeze/lost sheets).
  StreakOpenEvent? pendingOpenEvent;

  /// Called after every successful [recordPractice] with the new streak.
  /// Wired to notification rescheduling in a later phase.
  void Function(int streak)? onPracticeRecorded;

  int get currentStreak => _current;
  int get bestStreak => _best;
  int get totalPracticeDays => _totalDays;
  bool get isLoaded => _loaded;

  bool get practicedToday {
    final last = _lastDate;
    return last != null && _sameDate(last, _today);
  }

  DateTime get _today {
    final now = clock.now();
    return DateTime(now.year, now.month, now.day);
  }

  Future<QuizSettings> _prefs() async =>
      _settings ??= await QuizSettings.load();

  /// Load persisted state and evaluate the day gap. Call once at startup and
  /// again on app resume (a long-suspended app crosses midnights too).
  /// Safe to call repeatedly.
  Future<void> init() async {
    final s = await _prefs();
    if (!_loaded) {
      _current = await s.dailyStreakCurrent();
      _best = await s.dailyStreakBest();
      _totalDays = await s.dailyStreakTotalDays();
      _lastDate = _parseDate(await s.dailyStreakLastDate());
      _loaded = true;
    }
    await _evaluateGap(s);
    notifyListeners();
  }

  /// Applies the freeze or breaks the streak when day(s) were missed.
  Future<void> _evaluateGap(QuizSettings s) async {
    final last = _lastDate;
    if (last == null || _current == 0) return;
    final gap = _today.difference(last).inDays;
    // gap <= 1: today or yesterday — intact. gap < 0: clock/timezone moved
    // backwards — never break a streak over that.
    if (gap <= 1) return;
    if (gap == 2 && _isPro()) {
      // Missed exactly yesterday: Pro freeze repairs it once per ISO week.
      final week = _isoWeek(_today);
      if (await s.dailyStreakFreezeWeek() != week) {
        await s.setDailyStreakFreezeWeek(week);
        // Pretend yesterday was practiced so today's session extends normally.
        _lastDate = _today.subtract(const Duration(days: 1));
        await s.setDailyStreakLastDate(_formatDate(_lastDate!));
        pendingOpenEvent = StreakFrozen(_current);
        return;
      }
    }
    pendingOpenEvent = StreakLost(_current);
    _current = 0;
    await s.setDailyStreakCurrent(0);
  }

  /// Record a completed practice session. Idempotent per day: only the first
  /// call each local day extends the streak.
  Future<StreakUpdate> recordPractice() async {
    final s = await _prefs();
    if (!_loaded) await init();
    final today = _today;
    final last = _lastDate;
    if (last != null && _sameDate(last, today)) {
      return const StreakUpdate(isFirstToday: false);
    }
    final extendsStreak =
        last != null && _sameDate(last, today.subtract(const Duration(days: 1)));
    _current = extendsStreak ? _current + 1 : 1;
    if (_current > _best) _best = _current;
    _totalDays += 1;
    _lastDate = today;
    await s.setDailyStreakCurrent(_current);
    await s.setDailyStreakBest(_best);
    await s.setDailyStreakTotalDays(_totalDays);
    await s.setDailyStreakLastDate(_formatDate(today));
    notifyListeners();
    onPracticeRecorded?.call(_current);
    return StreakUpdate(
      isFirstToday: true,
      milestone: milestones.contains(_current) ? _current : null,
    );
  }

  /// The UI takes ownership of the pending open event (show a sheet once).
  StreakOpenEvent? consumeOpenEvent() {
    final e = pendingOpenEvent;
    pendingOpenEvent = null;
    return e;
  }

  static bool _sameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _formatDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static DateTime? _parseDate(String? s) {
    if (s == null) return null;
    final d = DateTime.tryParse(s);
    return d == null ? null : DateTime(d.year, d.month, d.day);
  }

  /// ISO-8601 week identifier, e.g. `2026-W28`. Weeks run Mon–Sun; week 1 is
  /// the week containing the first Thursday of the year.
  static String _isoWeek(DateTime date) {
    // Thursday of this date's week decides the week-year.
    final thursday = date.add(Duration(days: 4 - date.weekday));
    final firstDay = DateTime(thursday.year, 1, 1);
    final week = 1 + (thursday.difference(firstDay).inDays ~/ 7);
    return '${thursday.year}-W${week.toString().padLeft(2, '0')}';
  }
}
