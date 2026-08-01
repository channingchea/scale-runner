import 'social_backend.dart';
import 'social_models.dart';

/// In-memory backend seeded with sample friends/activity, purely to preview
/// the Friends UI without touching Supabase or signing in. Toggle via
/// `kMockSocialDataRequested` in social_config.dart; it only takes effect in
/// debug builds, so this class can never reach a release build.
///
/// Note [isSignedIn] returns true unconditionally — that is what makes the
/// Friends screen skip the sign-in card entirely while mock mode is on.
class MockSocialBackend implements SocialBackend {
  MockSocialBackend() {
    final now = DateTime.now();
    _friends = [
      _friend('mock-1', 'Jordan', '2:4', 42, 55,
          now.subtract(const Duration(days: 40))),
      _friend('mock-2', 'Sam Rivera', '9:2', 15, 30,
          now.subtract(const Duration(days: 12))),
      _friend('mock-3', 'Pianist 483', '5:6', 7, 7,
          now.subtract(const Duration(days: 3))),
      _friend('mock-4', 'Ilya K', '0:1', 3, 20,
          now.subtract(const Duration(days: 60))),
      _friend('mock-5', 'Maya', '11:7', 0, 12,
          now.subtract(const Duration(days: 90))),
    ];
    _applause = [
      ApplauseReceived(
        createdAt: now.subtract(const Duration(hours: 2)),
        from: _friends[0].profile,
        streakDays: 41,
        seen: false,
      ),
      ApplauseReceived(
        createdAt: now.subtract(const Duration(days: 1)),
        from: _friends[1].profile,
        streakDays: 15,
        seen: false,
      ),
      ApplauseReceived(
        createdAt: now.subtract(const Duration(days: 5)),
        from: _friends[3].profile,
        streakDays: 2,
        seen: true,
      ),
    ];
    _applaudedToday = {'mock-2'};
  }

  static FriendEntry _friend(String id, String name, String seed, int current,
          int best, DateTime since) =>
      FriendEntry(
        profile: SocialProfile(id: id, displayName: name, avatarSeed: seed),
        currentStreak: current,
        bestStreak: best,
        totalDays: best + 15,
        friendsSince: since,
      );

  late List<FriendEntry> _friends;
  late List<ApplauseReceived> _applause;
  late Set<String> _applaudedToday;

  @override
  bool get isSignedIn => true;

  @override
  String? get userId => 'me';

  @override
  Future<AuthResult> signInWithApple() async => const AuthSuccess();

  @override
  Future<AuthResult> signInWithGoogle() async => const AuthSuccess();

  @override
  Future<void> signOut() async {}

  @override
  Future<void> deleteAccount() async {}

  @override
  Future<SocialProfile?> myProfile() async => const SocialProfile(
      id: 'me', displayName: 'Channing', avatarSeed: '3:0');

  @override
  Future<void> upsertProfile(String displayName, String avatarSeed) async {}

  @override
  Future<void> upsertStreak(int current, int best, int totalDays) async {}

  @override
  Future<List<FriendEntry>> fetchFriends() async => _friends;

  @override
  Future<void> removeFriend(String otherId) async =>
      _friends = _friends.where((f) => f.profile.id != otherId).toList();

  @override
  Future<String> createInvite() async => 'MOCKCODE1';

  @override
  Future<InvitePreview?> invitePreview(String code) async =>
      const InvitePreview(
          inviterId: 'mock-1',
          displayName: 'Jordan',
          avatarSeed: '2:4',
          currentStreak: 42);

  @override
  Future<String?> acceptInvite(String code) async => null;

  @override
  Future<void> applaud(String toId, int streakDays) async =>
      _applaudedToday = {..._applaudedToday, toId};

  @override
  Future<List<ApplauseReceived>> fetchApplause() async => _applause;

  @override
  Future<Set<String>> applaudedTodayIds() async => _applaudedToday;

  @override
  Future<void> markApplauseSeen() async {
    _applause = [
      for (final a in _applause)
        ApplauseReceived(
            createdAt: a.createdAt,
            from: a.from,
            streakDays: a.streakDays,
            seen: true),
    ];
  }

  @override
  Future<void> upsertWeeklyStats(WeeklyStat stat) async {}

  @override
  Future<List<WeeklyStat>> fetchWeeklyStats(String userId,
      {int limit = 12}) async {
    final now = DateTime.now();
    final base = userId.hashCode.abs();
    final count = limit < 10 ? limit : 10;
    return [
      for (var i = 0; i < count; i++)
        _mockWeek(now.subtract(Duration(days: i * 7)), base + i * 7),
    ];
  }

  @override
  Future<void> upsertModeStats(ModeStats stats) async {}

  @override
  Future<ModeStats?> fetchModeStats(String userId) async {
    final seed = userId.hashCode.abs();
    // Vary counts/accuracy per user; 'me' gets a solid, playable profile.
    final runA = 200 + seed % 900;
    final jamA = seed % 400; // sometimes below the scoring threshold
    final invA = 50 + seed % 300;
    return ModeStats(
      runAttempts: runA,
      runCorrect: (runA * (0.6 + (seed % 30) / 100)).round(),
      jamAttempts: jamA,
      jamCorrect: (jamA * (0.5 + (seed % 40) / 100)).round(),
      invAttempts: invA,
      invCorrect: (invA * (0.4 + (seed % 35) / 100)).round(),
    );
  }

  static WeeklyStat _mockWeek(DateTime when, int seed) {
    final days = 2 + (seed % 5); // 2..6
    var mask = 0;
    for (var d = 0; d < days; d++) {
      mask |= 1 << ((seed + d * 3) % 7);
    }
    final sessions = days + (seed % 4);
    final attempts = sessions * (12 + (seed % 8));
    final correct = (attempts * (70 + (seed % 25)) / 100).round();
    return WeeklyStat(
      isoWeek: isoWeekOf(when),
      weekStart: weekStartOf(when),
      daysMask: mask,
      sessions: sessions,
      attempts: attempts,
      correct: correct,
    );
  }
}
