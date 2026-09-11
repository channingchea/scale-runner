import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../purchases/purchase_service.dart';
import '../quiz/quiz_settings.dart';
import '../streak/streak_service.dart';
import '../sync/mock_sync_backend.dart';
import '../sync/sync_backend.dart';
import '../sync/sync_service.dart';
import 'mock_social_backend.dart';
import 'social_backend.dart';
import 'social_config.dart';
import 'social_models.dart';

/// Everything social: optional sign-in, friends, applause, leaderboard data,
/// and the friends-facing totals (streak, this week, per-mode scores), which
/// SyncService asks it to refresh after every pull so they sum every device. Mirrors the app's service pattern (eager singleton,
/// ChangeNotifier, never-throwing init, injectable deps for tests).
///
/// The app is fully usable signed out — every method here degrades to a
/// no-op or a friendly error rather than blocking practice.
class SocialService extends ChangeNotifier {
  SocialService({
    this._backend,
    QuizSettings? settings,
    this._streakSource,
    SyncService? sync,
    PurchaseService? purchases,
  })  : _injectedSettings = settings,
        _sync = sync ?? SyncService.instance,
        _purchases = purchases ?? PurchaseService.instance;

  static final SocialService instance = SocialService();

  SocialBackend? _backend;
  final SyncService _sync;
  final PurchaseService _purchases;
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
          _sync.attach(MockSyncBackend(MockSyncServer()));
        } else {
          await Supabase.initialize(
              url: supabaseUrl, publishableKey: supabasePublishableKey);
          _backend = SupabaseSocialBackend(Supabase.instance.client);
          _sync.attach(SupabaseSyncBackend(Supabase.instance.client));
        }
      }
      _sync.onAggregates = _pushAggregates;
      final seen = await (await _settings).socialActivitySeenAt();
      if (seen != null) _activitySeenAt = DateTime.tryParse(seen)?.toLocal();
      if (isSignedIn) {
        unawaited(_sync.sync());
        unawaited(_purchases.linkAccount(_backend!.userId));
        _profile = await _backend!.myProfile();
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

  Future<String?> signInWithEmail(String email, String password) =>
      _signIn((b) => b.signInWithEmail(email, password));

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
          unawaited(refresh());
          unawaited(_sync.onSignedIn());
          unawaited(_purchases.linkAccount(backend.userId));
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
    await _sync.onSignedOut();
    unawaited(_purchases.linkAccount(null));
    _clearLocal();
  }

  /// Deletes the account server-side. Returns true on success. The device
  /// keeps its local copy of everything; only the server rows go.
  Future<bool> deleteAccount() async {
    try {
      await _backend?.deleteAccount();
      await _sync.onSignedOut();
      unawaited(_purchases.linkAccount(null));
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

  // ---- Friends-facing totals ----

  /// Called by SyncService after every pull. Friends read three rows about
  /// us (streak, this week, per-mode scores); each becomes the merged total
  /// over every device, so practicing on the iPad shows up for friends the
  /// same as practicing on the phone. Signed out this is a no-op and the
  /// local aggregates simply wait for the next sign-in.
  Future<void> _pushAggregates() async {
    final backend = _backend;
    if (backend == null || !isSignedIn) return;
    final settings = await _settings;
    final s = _readStreak();
    await backend.upsertStreak(s.current, s.best, s.total);
    final week = await settings.mergedWeeklyCurrent();
    if (week != null) await backend.upsertWeeklyStats(week);
    await backend.upsertModeStats(await settings.modeStats());
  }

  // ---- Weekly stats ----

  /// Record one finished practice-mode session (Scale Running / Jam /
  /// Inversion) into this week's local aggregate. Quizzes are intentionally
  /// excluded. The write itself wakes SyncService, which uploads this
  /// device's week and refreshes the friends-facing row. Never throws.
  Future<void> recordWeeklySession(int attempts, int correct) async {
    final settings = await _settings;
    final now = DateTime.now();
    var agg = WeeklyStat.decode(await settings.socialWeeklyCurrent());
    if (agg == null || agg.isoWeek != isoWeekOf(now)) {
      agg = WeeklyStat.empty(now);
    }
    agg = agg.withSession(now, attempts, correct);
    await settings.setSocialWeeklyCurrent(agg.encode());
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
