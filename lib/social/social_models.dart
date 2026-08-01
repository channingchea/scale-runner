import 'dart:math';

import 'package:flutter/material.dart';

/// A user's public identity: id + display name + generated avatar.
class SocialProfile {
  const SocialProfile({
    required this.id,
    required this.displayName,
    required this.avatarSeed,
  });

  final String id;
  final String displayName;
  final String avatarSeed;

  factory SocialProfile.fromRow(Map<String, dynamic> row) => SocialProfile(
        id: row['id'] as String,
        displayName: row['display_name'] as String? ?? 'Pianist',
        avatarSeed: row['avatar_seed'] as String? ?? '',
      );
}

/// A friend plus their synced streak, for the leaderboard/friends list.
class FriendEntry {
  const FriendEntry({
    required this.profile,
    required this.currentStreak,
    required this.bestStreak,
    this.totalDays = 0,
    required this.friendsSince,
  });

  final SocialProfile profile;
  final int currentStreak;
  final int bestStreak;
  final int totalDays;
  final DateTime friendsSince;
}

/// A friend's full profile: their leaderboard entry plus recent weekly stats.
class FriendProfileDetail {
  const FriendProfileDetail({
    required this.friend,
    required this.weeks,
    this.modeStats,
  });

  final FriendEntry friend;
  final List<WeeklyStat> weeks; // newest first
  final ModeStats? modeStats; // null if the friend has no scores yet

  /// This ISO week's stats, or an empty week when nothing's recorded yet.
  WeeklyStat get thisWeek {
    final iso = isoWeekOf(DateTime.now());
    for (final w in weeks) {
      if (w.isoWeek == iso) return w;
    }
    return WeeklyStat.empty(DateTime.now());
  }

  /// Recent weeks oldest→newest, for a trend chart.
  List<WeeklyStat> get trend => weeks.reversed.toList();
}

/// What the accept-invite screen shows before the tap.
class InvitePreview {
  const InvitePreview({
    required this.inviterId,
    required this.displayName,
    required this.avatarSeed,
    required this.currentStreak,
  });

  final String inviterId;
  final String displayName;
  final String avatarSeed;
  final int currentStreak;
}

/// One row in the activity feed.
sealed class ActivityItem {
  const ActivityItem({required this.createdAt});
  final DateTime createdAt;
}

/// A friend applauded your streak.
class ApplauseReceived extends ActivityItem {
  const ApplauseReceived({
    required super.createdAt,
    required this.from,
    required this.streakDays,
    required this.seen,
  });

  final SocialProfile? from; // null if the sender deleted their account
  final int streakDays;
  final bool seen;
}

/// A friendship was created (they accepted your invite, or you theirs).
class FriendJoined extends ActivityItem {
  const FriendJoined({required super.createdAt, required this.friend});

  final SocialProfile friend;
}

/// Sign-in outcomes surfaced by the backend.
sealed class AuthResult {
  const AuthResult();
}

class AuthSuccess extends AuthResult {
  const AuthSuccess({this.suggestedName});
  final String? suggestedName;
}

class AuthCancelled extends AuthResult {
  const AuthCancelled();
}

class AuthError extends AuthResult {
  const AuthError(this.message);
  final String message;
}

// ---- Avatars ----------------------------------------------------------
// A profile's avatar is derived from a tiny persisted seed: "e:c" indexing
// into fixed emoji/color lists. No photos, no uploads, no moderation risk.

const List<String> avatarEmojis = [
  '🎹', '🎵', '🎶', '🎸', '🥁', '🎷', '🎺', '🎻',
  '🪕', '🎤', '🎧', '🦊', '🐼', '🐸', '🦉', '🐙',
];

const List<Color> avatarColors = [
  Color(0xFF36D6C3), Color(0xFFF5A524), Color(0xFF8B7CF6), Color(0xFF4ADE80),
  Color(0xFFF4717F), Color(0xFF60A5FA), Color(0xFFF97316), Color(0xFFE879F9),
];

String randomAvatarSeed([Random? rng]) {
  final r = rng ?? Random();
  return '${r.nextInt(avatarEmojis.length)}:${r.nextInt(avatarColors.length)}';
}

/// Decodes a seed into (emoji, color); tolerant of bad/legacy values.
(String, Color) avatarFromSeed(String seed) {
  final parts = seed.split(':');
  final e = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 0 : 0;
  final c = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
  return (
    avatarEmojis[e % avatarEmojis.length],
    avatarColors[c % avatarColors.length],
  );
}

// ---- Display names ----------------------------------------------------
// v1 UGC filter: trim, collapse whitespace, strip control chars, cap at 24.

const int maxDisplayNameLength = 24;

/// Returns the cleaned name, or null if nothing usable remains.
String? sanitizeDisplayName(String raw) {
  var s = raw
      .replaceAll(RegExp(r'[\x00-\x1F\x7F]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (s.isEmpty) return null;
  if (s.length > maxDisplayNameLength) s = s.substring(0, maxDisplayNameLength).trim();
  return s.isEmpty ? null : s;
}

/// Fallback name when a provider gives us nothing.
String defaultDisplayName([Random? rng]) =>
    'Pianist ${100 + (rng ?? Random()).nextInt(900)}';

// ---- Weekly practice stats --------------------------------------------
// One ISO-week bucket of practice-mode activity (Scale Running / Jam /
// Inversion — quizzes excluded). daysMask is a 7-bit set, bit 0 = Monday.

class WeeklyStat {
  const WeeklyStat({
    required this.isoWeek,
    required this.weekStart,
    required this.daysMask,
    required this.sessions,
    required this.attempts,
    required this.correct,
  });

  final String isoWeek;
  final DateTime weekStart; // Monday, local date-only
  final int daysMask;
  final int sessions;
  final int attempts;
  final int correct;

  int get daysPracticed => _popcount7(daysMask);

  /// Fraction correct, or null when nothing was attempted this week.
  double? get accuracy => attempts == 0 ? null : correct / attempts;

  /// A copy with one more session folded in (sets that day's weekday bit).
  WeeklyStat withSession(DateTime day, int addAttempts, int addCorrect) =>
      WeeklyStat(
        isoWeek: isoWeek,
        weekStart: weekStart,
        daysMask: daysMask | (1 << (day.weekday - 1)),
        sessions: sessions + 1,
        attempts: attempts + addAttempts,
        correct: correct + addCorrect,
      );

  static WeeklyStat empty(DateTime when) => WeeklyStat(
        isoWeek: isoWeekOf(when),
        weekStart: weekStartOf(when),
        daysMask: 0,
        sessions: 0,
        attempts: 0,
        correct: 0,
      );

  Map<String, dynamic> toRow(String userId) => {
        'user_id': userId,
        'iso_week': isoWeek,
        'week_start': _ymd(weekStart),
        'days_mask': daysMask,
        'sessions': sessions,
        'attempts': attempts,
        'correct': correct,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

  factory WeeklyStat.fromRow(Map<String, dynamic> row) => WeeklyStat(
        isoWeek: row['iso_week'] as String,
        weekStart: DateTime.parse(row['week_start'] as String),
        daysMask: (row['days_mask'] as num?)?.toInt() ?? 0,
        sessions: (row['sessions'] as num?)?.toInt() ?? 0,
        attempts: (row['attempts'] as num?)?.toInt() ?? 0,
        correct: (row['correct'] as num?)?.toInt() ?? 0,
      );

  /// Local-storage form: "iso|yyyy-mm-dd|mask|sessions|attempts|correct".
  String encode() =>
      '$isoWeek|${_ymd(weekStart)}|$daysMask|$sessions|$attempts|$correct';

  static WeeklyStat? decode(String? s) {
    if (s == null) return null;
    final p = s.split('|');
    if (p.length != 6) return null;
    final ws = DateTime.tryParse(p[1]);
    if (ws == null) return null;
    return WeeklyStat(
      isoWeek: p[0],
      weekStart: ws,
      daysMask: int.tryParse(p[2]) ?? 0,
      sessions: int.tryParse(p[3]) ?? 0,
      attempts: int.tryParse(p[4]) ?? 0,
      correct: int.tryParse(p[5]) ?? 0,
    );
  }
}

int _popcount7(int m) {
  var n = 0;
  for (var i = 0; i < 7; i++) {
    if (m & (1 << i) != 0) n++;
  }
  return n;
}

String _ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Monday (local, date-only) of [when]'s week.
DateTime weekStartOf(DateTime when) {
  final d = DateTime(when.year, when.month, when.day);
  return d.subtract(Duration(days: d.weekday - 1));
}

/// ISO-8601 week id, e.g. "2026-W28". Weeks run Mon–Sun; week 1 holds the
/// year's first Thursday.
String isoWeekOf(DateTime when) {
  final date = DateTime(when.year, when.month, when.day);
  final thursday = date.add(Duration(days: 4 - date.weekday));
  final firstDay = DateTime(thursday.year, 1, 1);
  final week = 1 + (thursday.difference(firstDay).inDays ~/ 7);
  return '${thursday.year}-W${week.toString().padLeft(2, '0')}';
}

// ---- Mode overview scores ----------------------------------------------
// One 0–100 "how am I doing" score per practice mode (Scale Running / Jam /
// Inversion), blending lifetime accuracy with practice volume so a perfect
// run of a few notes can't outrank steady work over hundreds. Shareable:
// shown on your own Stats screen and on friends' profiles.

/// Plays below which a mode has too little data to score (shows "—").
const int kModeScoreMinPlays = 10;

/// Plays at which volume credit maxes out. Below it the score is scaled by
/// √(plays / this), so small samples can't inflate.
const int kModeScoreFullPlays = 300;

/// 0–100 overview score, or null when there's too little data.
int? modeScore(int attempts, int correct) {
  if (attempts < kModeScoreMinPlays) return null;
  final accuracy = correct / attempts;
  final volume = sqrt(attempts / kModeScoreFullPlays);
  return (100 * accuracy * (volume < 1 ? volume : 1)).round();
}

/// Lifetime practice-mode totals (raw plays + hits) for the three running
/// modes, plus derived overview scores. Synced so friends see your scores.
class ModeStats {
  const ModeStats({
    this.runAttempts = 0,
    this.runCorrect = 0,
    this.jamAttempts = 0,
    this.jamCorrect = 0,
    this.invAttempts = 0,
    this.invCorrect = 0,
  });

  final int runAttempts, runCorrect;
  final int jamAttempts, jamCorrect;
  final int invAttempts, invCorrect;

  int? get scaleRunningScore => modeScore(runAttempts, runCorrect);
  int? get jamScore => modeScore(jamAttempts, jamCorrect);
  int? get inversionScore => modeScore(invAttempts, invCorrect);

  Map<String, dynamic> toRow(String userId) => {
        'user_id': userId,
        'run_attempts': runAttempts,
        'run_correct': runCorrect,
        'jam_attempts': jamAttempts,
        'jam_correct': jamCorrect,
        'inv_attempts': invAttempts,
        'inv_correct': invCorrect,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

  factory ModeStats.fromRow(Map<String, dynamic> row) => ModeStats(
        runAttempts: (row['run_attempts'] as num?)?.toInt() ?? 0,
        runCorrect: (row['run_correct'] as num?)?.toInt() ?? 0,
        jamAttempts: (row['jam_attempts'] as num?)?.toInt() ?? 0,
        jamCorrect: (row['jam_correct'] as num?)?.toInt() ?? 0,
        invAttempts: (row['inv_attempts'] as num?)?.toInt() ?? 0,
        invCorrect: (row['inv_correct'] as num?)?.toInt() ?? 0,
      );
}
