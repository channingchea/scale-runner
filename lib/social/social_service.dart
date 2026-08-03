import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../quiz/quiz_settings.dart';
import '../streak/streak_service.dart';
import 'mock_social_backend.dart';
import 'social_backend.dart';
import 'social_config.dart';
import 'social_models.dart';

/// Everything social: optional sign-in, streak sync, friends, applause,
/// leaderboard data. Mirrors the app's service pattern (eager singleton,
/// ChangeNotifier, never-throwing init, injectable deps for tests).
///
/// The app is fully usable signed out — every method here degrades to a
/// no-op or a friendly error rather than blocking practice.
class SocialService extends ChangeNotifier {
  SocialService({
    this._backend,
    QuizSettings? settings,
    this._streakSource,
  }) : _injectedSettings = settings;

  static final SocialService instance = SocialService();

  SocialBackend? _backend;
  final QuizSettings? _injectedSettings;
  final ({int current, int best, int total}) Function()? _streakSource;

  Future<void>? _initFuture;
  bool _loading = false;
  SocialProfile? _profile;
  List<FriendEntry> _friends = const [];
  List<ApplauseReceived> _applause = const [];
  Set<String> _applaudedToday = const {};
  DateTime? _activitySeenAt;

  // ---- State ----

  bool get isSignedIn => _backend?.isSignedIn ?? false;
  SocialProfile? get profile => _profile;
  bool get loading => _loading;

  /// Friends sorted by current streak (the leaderboard order).
  List<FriendEntry> get friends => _friends;

  /// The full activity feed: applause received + friends joined, newest first.
  List<ActivityItem> get activity {
    final items = <ActivityItem>[
      ..._applause,
      for (final f in _friends)
        FriendJoined(createdAt: f.friendsSince, friend: f.profile),
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return items.length > 50 ? items.sublist(0, 50) : items;
  }

  int get unreadCount {
    var n = _applause.where((a) => !a.seen).length;
    final seenAt = _activitySeenAt;
    for (final f in _friends) {
      if (seenAt == null || f.friendsSince.isAfter(seenAt)) n++;
    }
    return n;
  }

  bool applaudedToday(String friendId) => _applaudedToday.contains(friendId);

  Future<QuizSettings> get _settings async =>
      _injectedSettings ?? await QuizSettings.load();

  ({int current, int best, int total}) _readStreak() =>
      _streakSource?.call() ??
      (
        current: StreakService.instance.currentStreak,
        best: StreakService.instance.bestStreak,
        total: StreakService.instance.totalPracticeDays,
      );

  // ---- Lifecycle ----

  /// Safe to call more than once; never throws (social must not break the
  /// offline app). All callers share one future, so awaiting it guarantees
  /// the backend is ready — the invite screen relies on that when the app is
  /// cold-started from a deep link while main()'s init is still running.
  Future<void> init() => _initFuture ??= _init();

  Future<void> _init() async {
    try {
      if (_backend == null) {
        if (kMockSocialData) {
          _backend = MockSocialBackend();
        } else {
          await Supabase.initialize(
              url: supabaseUrl, publishableKey: supabasePublishableKey);
          _backend = SupabaseSocialBackend(Supabase.instance.client);
        }
      }
      final seen = await (await _settings).socialActivitySeenAt();
      if (seen != null) _activitySeenAt = DateTime.tryParse(seen)?.toLocal();
      if (isSignedIn) {
        _profile = await _backend!.myProfile();
        await _flushPendingStreak();
        await refresh();
      }
    } catch (e) {
      debugPrint('SocialService init failed: $e');
    }
    notifyListeners();
  }

  /// Re-fetch friends, applause, and today's applauded set.
  Future<void> refresh() async {
    final backend = _backend;
    if (backend == null || !isSignedIn) return;
    _loading = true;
    notifyListeners();
    try {
      final results = await Future.wait([
        backend.fetchFriends(),
        backend.fetchApplause(),
        backend.applaudedTodayIds(),
      ]);
      _friends = (results[0] as List<FriendEntry>)
        ..sort((a, b) => b.currentStreak.compareTo(a.currentStreak));
      _applause = results[1] as List<ApplauseReceived>;
      _applaudedToday = results[2] as Set<String>;
      await _flushPendingStreak();
      await _flushWeekly();
      await _flushModeStats();
    } catch (e) {
      debugPrint('SocialService refresh failed: $e');
    }
    _loading = false;
    notifyListeners();
  }

  // ---- Auth ----

  /// Returns null on success or cancel, else a user-facing error message.
  Future<String?> signInWithApple() => _signIn((b) => b.signInWithApple());

  Future<String?> signInWithGoogle() => _signIn((b) => b.signInWithGoogle());

  Future<String?> _signIn(
      Future<AuthResult> Function(SocialBackend) doSignIn) async {
    final backend = _backend;
    if (backend == null) return 'Social features aren\'t available.';
    final result = await doSignIn(backend);
    switch (result) {
      case AuthCancelled():
        return null;
      case AuthError(:final message):
        return message;
      case AuthSuccess(:final suggestedName):
        try {
          await _ensureProfile(suggestedName);
          await _flushPendingStreak();
          unawaited(syncStreak());
          unawaited(refresh());
        } catch (e) {
          debugPrint('post-sign-in setup failed: $e');
        }
        notifyListeners();
        return null;
    }
  }

  Future<void> _ensureProfile(String? suggestedName) async {
    final backend = _backend!;
    _profile = await backend.myProfile();
    if (_profile != null) return;
    final name = sanitizeDisplayName(suggestedName ?? '') ??
        defaultDisplayName();
    final seed = randomAvatarSeed();
    await backend.upsertProfile(name, seed);
    _profile = SocialProfile(
        id: backend.userId!, displayName: name, avatarSeed: seed);
  }

  /// Returns null on success, else an error message.
  Future<String?> renameProfile(String raw) async {
    final backend = _backend;
    final p = _profile;
    if (backend == null || p == null) return 'Not signed in.';
    final name = sanitizeDisplayName(raw);
    if (name == null) return 'Enter a name (up to 24 characters).';
    try {
      await backend.upsertProfile(name, p.avatarSeed);
      _profile =
          SocialProfile(id: p.id, displayName: name, avatarSeed: p.avatarSeed);
      notifyListeners();
      return null;
    } catch (e) {
      return 'Couldn\'t save the name. Check your connection.';
    }
  }

  /// Updates the avatar seed ("emoji:color"). Returns null on success, else an
  /// error message.
  Future<String?> updateAvatar(String seed) async {
    final backend = _backend;
    final p = _profile;
    if (backend == null || p == null) return 'Not signed in.';
    try {
      await backend.upsertProfile(p.displayName, seed);
      _profile =
          SocialProfile(id: p.id, displayName: p.displayName, avatarSeed: seed);
      notifyListeners();
      return null;
    } catch (e) {
      return 'Couldn\'t save the avatar. Check your connection.';
    }
  }

  Future<void> signOut() async {
    try {
      await _backend?.signOut();
    } catch (e) {
      debugPrint('sign-out failed: $e');
    }
    _clearLocal();
  }

  /// Deletes the account server-side. Returns true on success.
  Future<bool> deleteAccount() async {
    try {
      await _backend?.deleteAccount();
      _clearLocal();
      return true;
    } catch (e) {
      debugPrint('delete account failed: $e');
      return false;
    }
  }

  void _clearLocal() {
    _profile = null;
    _friends = const [];
    _applause = const [];
    _applaudedToday = const {};
    notifyListeners();
  }

  // ---- Streak sync ----

  /// Fire-and-forget push of the local streak. Called from the practice
  /// hook; when offline the payload is queued and retried on init/refresh.
  Future<void> syncStreak() async {
    final backend = _backend;
    if (backend == null || !isSignedIn) return;
    final s = _readStreak();
    final settings = await _settings;
    await settings
        .setSocialPendingStreak('${s.current}|${s.best}|${s.total}');
    try {
      await backend.upsertStreak(s.current, s.best, s.total);
      await settings.setSocialPendingStreak(null);
    } catch (e) {
      debugPrint('streak sync queued (offline?): $e');
    }
  }

  Future<void> _flushPendingStreak() async {
    final backend = _backend;
    if (backend == null || !isSignedIn) return;
    final settings = await _settings;
    final pending = await settings.socialPendingStreak();
    if (pending == null) return;
    final parts = pending.split('|');
    if (parts.length != 3) {
      await settings.setSocialPendingStreak(null);
      return;
    }
    try {
      await backend.upsertStreak(
        int.tryParse(parts[0]) ?? 0,
        int.tryParse(parts[1]) ?? 0,
        int.tryParse(parts[2]) ?? 0,
      );
      await settings.setSocialPendingStreak(null);
    } catch (_) {
      // still offline — keep it queued
    }
  }

  // ---- Weekly stats ----

  /// Record one finished practice-mode session (Scale Running / Jam /
  /// Inversion) into this week's local aggregate and push it. Quizzes are
  /// intentionally excluded. Accumulates locally even when signed out and
  /// syncs on the next sign-in. Fire-and-forget; never throws.
  Future<void> recordWeeklySession(int attempts, int correct) async {
    final settings = await _settings;
    final now = DateTime.now();
    var agg = WeeklyStat.decode(await settings.socialWeeklyCurrent());
    if (agg == null || agg.isoWeek != isoWeekOf(now)) {
      agg = WeeklyStat.empty(now);
    }
    agg = agg.withSession(now, attempts, correct);
    await settings.setSocialWeeklyCurrent(agg.encode());
    await settings.setSocialWeeklyDirty(true);
    await _pushWeekly(agg, settings);
  }

  /// Sums a session's `key → (attempts, correct)` snapshot and records it.
  Future<void> recordWeeklySessionFrom(Map<String, (int, int)> snapshot) {
    var a = 0, c = 0;
    for (final v in snapshot.values) {
      a += v.$1;
      c += v.$2;
    }
    return recordWeeklySession(a, c);
  }

  Future<void> _pushWeekly(WeeklyStat agg, QuizSettings settings) async {
    final backend = _backend;
    if (backend == null || !isSignedIn) return; // stays dirty; flush later
    try {
      await backend.upsertWeeklyStats(agg);
      await settings.setSocialWeeklyDirty(false);
    } catch (e) {
      debugPrint('weekly sync queued (offline?): $e');
    }
  }

  Future<void> _flushWeekly() async {
    final backend = _backend;
    if (backend == null || !isSignedIn) return;
    final settings = await _settings;
    if (!await settings.socialWeeklyDirty()) return;
    final agg = WeeklyStat.decode(await settings.socialWeeklyCurrent());
    if (agg == null) {
      await settings.setSocialWeeklyDirty(false);
      return;
    }
    await _pushWeekly(agg, settings);
  }

  /// A friend's recent weekly aggregates for the profile screen (newest first).
  Future<List<WeeklyStat>> weeklyStatsFor(String userId) async {
    try {
      return await _backend?.fetchWeeklyStats(userId) ?? const [];
    } catch (e) {
      debugPrint('fetch weekly stats failed: $e');
      return const [];
    }
  }

  /// Assembles a friend's profile: their leaderboard entry, recent weeks, and
  /// per-mode overview scores.
  Future<FriendProfileDetail> loadFriendProfile(FriendEntry friend) async {
    final results = await Future.wait([
      weeklyStatsFor(friend.profile.id),
      modeStatsFor(friend.profile.id),
    ]);
    return FriendProfileDetail(
      friend: friend,
      weeks: results[0] as List<WeeklyStat>,
      modeStats: results[1] as ModeStats?,
    );
  }

  // ---- Mode overview scores ----

  /// Recompute the lifetime per-mode totals from local settings and push them,
  /// so friends see up-to-date overview scores. Call from a practice
  /// session-end hook (after the mode's lifetime aggregates are merged).
  /// Accumulates locally when signed out and syncs on the next sign-in.
  /// Fire-and-forget; never throws.
  Future<void> recordModeScores() async {
    final settings = await _settings;
    await settings.setSocialModeStatsDirty(true);
    await _pushModeStats(settings);
  }

  Future<void> _pushModeStats(QuizSettings settings) async {
    final backend = _backend;
    if (backend == null || !isSignedIn) return; // stays dirty; flush later
    try {
      await backend.upsertModeStats(await settings.modeStats());
      await settings.setSocialModeStatsDirty(false);
    } catch (e) {
      debugPrint('mode-stats sync queued (offline?): $e');
    }
  }

  Future<void> _flushModeStats() async {
    final backend = _backend;
    if (backend == null || !isSignedIn) return;
    final settings = await _settings;
    if (!await settings.socialModeStatsDirty()) return;
    await _pushModeStats(settings);
  }

  /// A user's per-mode totals for the profile screen, or null if none yet.
  Future<ModeStats?> modeStatsFor(String userId) async {
    try {
      return await _backend?.fetchModeStats(userId);
    } catch (e) {
      debugPrint('fetch mode stats failed: $e');
      return null;
    }
  }

  // ---- Friends / invites ----

  /// Creates an invite and returns the share URL, or null on failure.
  Future<String?> createInviteUrl() async {
    final backend = _backend;
    if (backend == null || !isSignedIn) return null;
    try {
      final code = await backend.createInvite();
      return '$inviteBaseUrl/$code';
    } catch (e) {
      debugPrint('create invite failed: $e');
      return null;
    }
  }

  Future<InvitePreview?> previewInvite(String code) async {
    try {
      return await _backend?.invitePreview(code);
    } catch (e) {
      debugPrint('invite preview failed: $e');
      return null;
    }
  }

  /// Returns null on success, else an error message.
  Future<String?> acceptInvite(String code) async {
    final backend = _backend;
    if (backend == null || !isSignedIn) return 'Sign in first.';
    try {
      final error = await backend.acceptInvite(code);
      if (error == null) unawaited(refresh());
      return error;
    } catch (e) {
      return 'Couldn\'t accept the invite. Check your connection.';
    }
  }

  Future<void> removeFriend(String friendId) async {
    try {
      await _backend?.removeFriend(friendId);
      _friends =
          _friends.where((f) => f.profile.id != friendId).toList();
      notifyListeners();
    } catch (e) {
      debugPrint('remove friend failed: $e');
    }
  }

  // ---- Applause / activity ----

  /// One tap of applause for a friend's streak. Rate-limited to one per
  /// friend per day (enforced server-side too). Returns true if it counted.
  Future<bool> applaud(FriendEntry friend) async {
    final backend = _backend;
    if (backend == null || !isSignedIn) return false;
    if (_applaudedToday.contains(friend.profile.id)) return false;
    _applaudedToday = {..._applaudedToday, friend.profile.id};
    notifyListeners();
    try {
      await backend.applaud(friend.profile.id, friend.currentStreak);
      return true;
    } catch (e) {
      _applaudedToday = {..._applaudedToday}..remove(friend.profile.id);
      notifyListeners();
      return false;
    }
  }

  /// Marks the whole feed read (badge → 0).
  Future<void> markActivitySeen() async {
    _activitySeenAt = DateTime.now();
    _applause = [
      for (final a in _applause)
        ApplauseReceived(
          createdAt: a.createdAt,
          from: a.from,
          streakDays: a.streakDays,
          seen: true,
        ),
    ];
    notifyListeners();
    try {
      final settings = await _settings;
      await settings.setSocialActivitySeenAt(
          DateTime.now().toUtc().toIso8601String());
      await _backend?.markApplauseSeen();
    } catch (e) {
      debugPrint('mark seen failed: $e');
    }
  }
}
