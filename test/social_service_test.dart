import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:scale_runner/quiz/quiz_settings.dart';
import 'package:scale_runner/social/social_backend.dart';
import 'package:scale_runner/social/social_config.dart';
import 'package:scale_runner/social/social_models.dart';
import 'package:scale_runner/social/social_service.dart';

/// In-memory backend (house style: hand-rolled fakes + injection).
class FakeBackend implements SocialBackend {
  bool signedIn = false;
  bool offline = false; // remote calls throw when true
  SocialProfile? profileRow;
  (int, int, int)? streakRow;
  int streakUpserts = 0;
  List<FriendEntry> friends = [];
  List<ApplauseReceived> applauseRows = [];
  Set<String> applaudedToday = {};
  final List<(String, int)> applauseGiven = [];
  String? removedFriendId;
  bool deleted = false;
  String? acceptedCode;
  String? acceptError;

  void _checkOnline() {
    if (offline) throw Exception('offline');
  }

  @override
  bool get isSignedIn => signedIn;

  @override
  String? get userId => signedIn ? 'me' : null;

  @override
  Future<AuthResult> signInWithApple() async {
    signedIn = true;
    return const AuthSuccess(suggestedName: 'Channing');
  }

  @override
  Future<AuthResult> signInWithGoogle() async {
    signedIn = true;
    return const AuthSuccess();
  }

  @override
  Future<void> signOut() async => signedIn = false;

  @override
  Future<void> deleteAccount() async {
    deleted = true;
    signedIn = false;
  }

  @override
  Future<SocialProfile?> myProfile() async {
    _checkOnline();
    return profileRow;
  }

  @override
  Future<void> upsertProfile(String displayName, String avatarSeed) async {
    _checkOnline();
    profileRow = SocialProfile(
        id: 'me', displayName: displayName, avatarSeed: avatarSeed);
  }

  @override
  Future<void> upsertStreak(int current, int best, int totalDays) async {
    _checkOnline();
    streakUpserts++;
    streakRow = (current, best, totalDays);
  }

  @override
  Future<List<FriendEntry>> fetchFriends() async {
    _checkOnline();
    return friends;
  }

  @override
  Future<void> removeFriend(String otherId) async {
    _checkOnline();
    removedFriendId = otherId;
  }

  @override
  Future<String> createInvite() async {
    _checkOnline();
    return 'CODE123';
  }

  @override
  Future<InvitePreview?> invitePreview(String code) async {
    _checkOnline();
    return const InvitePreview(
        inviterId: 'x',
        displayName: 'Alice',
        avatarSeed: '1:1',
        currentStreak: 5);
  }

  @override
  Future<String?> acceptInvite(String code) async {
    _checkOnline();
    acceptedCode = code;
    return acceptError;
  }

  @override
  Future<void> applaud(String toId, int streakDays) async {
    _checkOnline();
    applauseGiven.add((toId, streakDays));
  }

  @override
  Future<List<ApplauseReceived>> fetchApplause() async {
    _checkOnline();
    return applauseRows;
  }

  @override
  Future<Set<String>> applaudedTodayIds() async {
    _checkOnline();
    return applaudedToday;
  }

  @override
  Future<void> markApplauseSeen() async {
    _checkOnline();
    applauseRows = [
      for (final a in applauseRows)
        ApplauseReceived(
            createdAt: a.createdAt,
            from: a.from,
            streakDays: a.streakDays,
            seen: true),
    ];
  }

  final List<WeeklyStat> weeklyUpserts = [];
  Map<String, List<WeeklyStat>> weeklyByUser = {};

  @override
  Future<void> upsertWeeklyStats(WeeklyStat stat) async {
    _checkOnline();
    weeklyUpserts.add(stat);
  }

  @override
  Future<List<WeeklyStat>> fetchWeeklyStats(String userId,
      {int limit = 12}) async {
    _checkOnline();
    return weeklyByUser[userId] ?? const [];
  }

  final List<ModeStats> modeUpserts = [];
  Map<String, ModeStats> modeByUser = {};

  @override
  Future<void> upsertModeStats(ModeStats stats) async {
    _checkOnline();
    modeUpserts.add(stats);
  }

  @override
  Future<ModeStats?> fetchModeStats(String userId) async {
    _checkOnline();
    return modeByUser[userId];
  }
}

FriendEntry friend(String id, String name, int streak, {DateTime? since}) =>
    FriendEntry(
      profile: SocialProfile(id: id, displayName: name, avatarSeed: '0:0'),
      currentStreak: streak,
      bestStreak: streak,
      friendsSince: since ?? DateTime(2026, 7, 1),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late QuizSettings settings;
  late FakeBackend backend;
  var localStreak = (current: 3, best: 7, total: 20);

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    settings = await QuizSettings.load();
    backend = FakeBackend();
    localStreak = (current: 3, best: 7, total: 20);
  });

  SocialService fresh() => SocialService(
        backend: backend,
        settings: settings,
        streakSource: () => localStreak,
      );

  group('sign-in and profile', () {
    test('creates a profile with provider name + generated avatar', () async {
      final s = fresh();
      await s.init();
      final error = await s.signInWithApple();
      expect(error, isNull);
      expect(s.isSignedIn, isTrue);
      expect(s.profile?.displayName, 'Channing');
      expect(s.profile?.avatarSeed, isNotEmpty);
    });

    test('keeps the existing profile on later sign-ins', () async {
      backend.profileRow = const SocialProfile(
          id: 'me', displayName: 'Old Name', avatarSeed: '2:3');
      final s = fresh();
      await s.init();
      await s.signInWithApple();
      expect(s.profile?.displayName, 'Old Name');
    });

    test('falls back to a default name when provider gives none', () async {
      final s = fresh();
      await s.init();
      await s.signInWithGoogle();
      expect(s.profile?.displayName, startsWith('Pianist '));
    });

    test('sign-out clears local social state', () async {
      backend.friends = [friend('f1', 'Alice', 5)];
      final s = fresh();
      await s.init();
      await s.signInWithApple();
      await s.refresh();
      expect(s.friends, isNotEmpty);
      await s.signOut();
      expect(s.isSignedIn, isFalse);
      expect(s.friends, isEmpty);
      expect(s.profile, isNull);
    });

    test('deleteAccount calls backend and clears state', () async {
      final s = fresh();
      await s.init();
      await s.signInWithApple();
      expect(await s.deleteAccount(), isTrue);
      expect(backend.deleted, isTrue);
      expect(s.profile, isNull);
    });

    test('rename validates and persists', () async {
      final s = fresh();
      await s.init();
      await s.signInWithApple();
      expect(await s.renameProfile('   '), isNotNull); // rejected
      expect(await s.renameProfile('  New\nName  '), isNull);
      expect(s.profile?.displayName, 'New Name');
    });

    test('updateAvatar persists a new seed', () async {
      final s = fresh();
      await s.init();
      await s.signInWithApple();
      expect(await s.updateAvatar('7:3'), isNull);
      expect(s.profile?.avatarSeed, '7:3');
    });
  });

  group('streak sync', () {
    test('pushes the local streak after practice', () async {
      final s = fresh();
      await s.init();
      await s.signInWithApple();
      backend.streakUpserts = 0;
      localStreak = (current: 4, best: 7, total: 21);
      await s.syncStreak();
      expect(backend.streakRow, (4, 7, 21));
      expect(await settings.socialPendingStreak(), isNull);
    });

    test('queues when offline and flushes on refresh', () async {
      final s = fresh();
      await s.init();
      await s.signInWithApple();
      backend.offline = true;
      await s.syncStreak();
      expect(backend.streakRow, isNull);
      expect(await settings.socialPendingStreak(), '3|7|20');
      backend.offline = false;
      await s.refresh();
      expect(backend.streakRow, (3, 7, 20));
      expect(await settings.socialPendingStreak(), isNull);
    });

    test('does nothing signed out', () async {
      final s = fresh();
      await s.init();
      await s.syncStreak();
      expect(backend.streakUpserts, 0);
      expect(await settings.socialPendingStreak(), isNull);
    });
  });

  group('friends and leaderboard order', () {
    test('friends sort by current streak descending', () async {
      backend.friends = [
        friend('a', 'Low', 1),
        friend('b', 'High', 9),
        friend('c', 'Mid', 4),
      ];
      final s = fresh();
      await s.init();
      await s.signInWithApple();
      await s.refresh();
      expect([for (final f in s.friends) f.profile.displayName],
          ['High', 'Mid', 'Low']);
    });

    test('removeFriend hits backend and updates the list', () async {
      backend.friends = [friend('a', 'Alice', 2), friend('b', 'Bob', 3)];
      final s = fresh();
      await s.init();
      await s.signInWithApple();
      await s.refresh();
      await s.removeFriend('a');
      expect(backend.removedFriendId, 'a');
      expect(s.friends.length, 1);
      expect(s.friends.first.profile.id, 'b');
    });
  });

  group('invites', () {
    test('createInviteUrl builds the share link', () async {
      final s = fresh();
      await s.init();
      await s.signInWithApple();
      expect(await s.createInviteUrl(), '$inviteBaseUrl/CODE123');
    });

    test('acceptInvite passes through backend result', () async {
      final s = fresh();
      await s.init();
      await s.signInWithApple();
      expect(await s.acceptInvite('CODE123'), isNull);
      expect(backend.acceptedCode, 'CODE123');
      backend.acceptError = 'This invite was already used.';
      expect(await s.acceptInvite('CODE123'), contains('already used'));
    });

    test('acceptInvite requires sign-in', () async {
      final s = fresh();
      await s.init();
      expect(await s.acceptInvite('CODE123'), isNotNull);
      expect(backend.acceptedCode, isNull);
    });
  });

  group('applause and activity', () {
    test('applaud sends streak days and marks the friend done today',
        () async {
      final f = friend('a', 'Alice', 6);
      backend.friends = [f];
      final s = fresh();
      await s.init();
      await s.signInWithApple();
      await s.refresh();
      expect(await s.applaud(f), isTrue);
      expect(backend.applauseGiven, [('a', 6)]);
      expect(s.applaudedToday('a'), isTrue);
      // Second tap the same day is rejected locally.
      expect(await s.applaud(f), isFalse);
      expect(backend.applauseGiven.length, 1);
    });

    test('failed applause rolls back the local rate-limit mark', () async {
      final f = friend('a', 'Alice', 6);
      backend.friends = [f];
      final s = fresh();
      await s.init();
      await s.signInWithApple();
      await s.refresh();
      backend.offline = true;
      expect(await s.applaud(f), isFalse);
      expect(s.applaudedToday('a'), isFalse);
    });

    test('unread badge counts unseen applause + new friends, and clears',
        () async {
      backend.friends = [
        friend('a', 'Alice', 2, since: DateTime(2026, 7, 13)),
      ];
      backend.applauseRows = [
        ApplauseReceived(
            createdAt: DateTime(2026, 7, 13, 10),
            from: backend.friends.first.profile,
            streakDays: 2,
            seen: false),
        ApplauseReceived(
            createdAt: DateTime(2026, 7, 12, 10),
            from: backend.friends.first.profile,
            streakDays: 1,
            seen: true),
      ];
      final s = fresh();
      await s.init();
      await s.signInWithApple();
      await s.refresh();
      expect(s.unreadCount, 2); // 1 unseen applause + 1 new friendship
      await s.markActivitySeen();
      expect(s.unreadCount, 0);
      expect(s.activity.length, 3); // 2 applause + 1 friend-joined
    });

    test('activity feed is newest-first', () async {
      backend.friends = [
        friend('a', 'Alice', 2, since: DateTime(2026, 7, 10)),
      ];
      backend.applauseRows = [
        ApplauseReceived(
            createdAt: DateTime(2026, 7, 12),
            from: null,
            streakDays: 3,
            seen: true),
      ];
      final s = fresh();
      await s.init();
      await s.signInWithApple();
      await s.refresh();
      expect(s.activity.first, isA<ApplauseReceived>());
      expect(s.activity.last, isA<FriendJoined>());
    });
  });

  group('weekly stats', () {
    test('records a session into this week and pushes it', () async {
      final s = fresh();
      await s.init();
      await s.signInWithApple();
      await s.recordWeeklySession(10, 8);
      final row = backend.weeklyUpserts.last;
      expect(row.sessions, 1);
      expect(row.attempts, 10);
      expect(row.correct, 8);
      expect(row.daysPracticed, 1);
      expect(await settings.socialWeeklyDirty(), isFalse);
    });

    test('two sessions same day = 1 day, summed', () async {
      final s = fresh();
      await s.init();
      await s.signInWithApple();
      await s.recordWeeklySession(10, 6);
      await s.recordWeeklySession(4, 4);
      final row = backend.weeklyUpserts.last;
      expect(row.sessions, 2);
      expect(row.attempts, 14);
      expect(row.correct, 10);
      expect(row.daysPracticed, 1);
    });

    test('recordWeeklySessionFrom sums a snapshot', () async {
      final s = fresh();
      await s.init();
      await s.signInWithApple();
      await s.recordWeeklySessionFrom({'C': (5, 4), 'G': (3, 2)});
      final row = backend.weeklyUpserts.last;
      expect(row.attempts, 8);
      expect(row.correct, 6);
    });

    test('queues when offline and flushes on refresh', () async {
      final s = fresh();
      await s.init();
      await s.signInWithApple();
      backend.offline = true;
      await s.recordWeeklySession(10, 8);
      expect(backend.weeklyUpserts, isEmpty);
      expect(await settings.socialWeeklyDirty(), isTrue);
      backend.offline = false;
      await s.refresh();
      expect(backend.weeklyUpserts, isNotEmpty);
      expect(await settings.socialWeeklyDirty(), isFalse);
    });

    test('weeklyStatsFor passes through the backend', () async {
      backend.weeklyByUser['f1'] = [WeeklyStat.empty(DateTime(2026, 7, 20))];
      final s = fresh();
      await s.init();
      await s.signInWithApple();
      expect((await s.weeklyStatsFor('f1')).length, 1);
    });
  });

  group('mode scores', () {
    test('modeScore: null under minimum, blends accuracy and volume', () {
      expect(modeScore(0, 0), isNull);
      expect(modeScore(9, 9), isNull); // below kModeScoreMinPlays
      expect(modeScore(300, 300), 100); // full volume, perfect
      expect(modeScore(300, 228), 76); // full volume, 76%
      expect(modeScore(1200, 900), 75); // volume capped at 1
      expect(modeScore(30, 30), 32); // 100% but discounted by √(30/300)
      expect(modeScore(30, 30)!, lessThan(modeScore(300, 300)!));
    });

    test('ModeStats derives scores and roundtrips a row', () {
      const m = ModeStats(
        runAttempts: 300,
        runCorrect: 228,
        jamAttempts: 4,
        jamCorrect: 4,
        invAttempts: 300,
        invCorrect: 96,
      );
      expect(m.scaleRunningScore, 76);
      expect(m.jamScore, isNull); // too few plays
      expect(m.inversionScore, 32);
      final r = ModeStats.fromRow(m.toRow('me'));
      expect(r.runAttempts, 300);
      expect(r.invCorrect, 96);
    });

    test('QuizSettings.modeStats sums the running aggregates', () async {
      await settings.mergeRunStats(
          {'C Major': (10, 8), 'G Major': (6, 3)}, {'Ionian': (16, 11)});
      await settings.mergeJamStats({'maj7': (5, 5)}, {'I': (5, 5)});
      await settings.mergeInversionStats({'Major': (7, 2)});
      final m = await settings.modeStats();
      expect((m.runAttempts, m.runCorrect), (16, 11));
      expect((m.jamAttempts, m.jamCorrect), (5, 5));
      expect((m.invAttempts, m.invCorrect), (7, 2));
    });

    test('records mode scores after practice and pushes them', () async {
      final s = fresh();
      await s.init();
      await s.signInWithApple();
      await settings.mergeRunStats(
          {'C Major': (300, 228)}, {'Ionian': (300, 228)});
      await s.recordModeScores();
      expect(backend.modeUpserts.last.scaleRunningScore, 76);
      expect(await settings.socialModeStatsDirty(), isFalse);
    });

    test('queues mode scores when offline and flushes on refresh', () async {
      final s = fresh();
      await s.init();
      await s.signInWithApple();
      backend.offline = true;
      await s.recordModeScores();
      expect(backend.modeUpserts, isEmpty);
      expect(await settings.socialModeStatsDirty(), isTrue);
      backend.offline = false;
      await s.refresh();
      expect(backend.modeUpserts, isNotEmpty);
      expect(await settings.socialModeStatsDirty(), isFalse);
    });

    test('modeStatsFor passes through the backend', () async {
      backend.modeByUser['f1'] =
          const ModeStats(runAttempts: 300, runCorrect: 228);
      final s = fresh();
      await s.init();
      await s.signInWithApple();
      final m = await s.modeStatsFor('f1');
      expect(m?.scaleRunningScore, 76);
    });
  });

  group('models', () {
    test('sanitizeDisplayName trims, collapses, caps', () {
      expect(sanitizeDisplayName('  a   b  '), 'a b');
      expect(sanitizeDisplayName(' '), isNull);
      expect(sanitizeDisplayName(''), isNull);
      expect(sanitizeDisplayName('x' * 40)!.length, maxDisplayNameLength);
    });

    test('avatar seed roundtrip tolerates junk', () {
      final (e1, c1) = avatarFromSeed('3:5');
      expect(e1, avatarEmojis[3]);
      expect(c1, avatarColors[5]);
      expect(() => avatarFromSeed(''), returnsNormally);
      expect(() => avatarFromSeed('999:999'), returnsNormally);
      expect(() => avatarFromSeed('nonsense'), returnsNormally);
    });

    test('inviteCodeFromUri parses both link forms only', () {
      expect(
          inviteCodeFromUri(
              Uri.parse('https://scalerunner.c1gnus.com/invite/ABC23')),
          'ABC23');
      expect(inviteCodeFromUri(Uri.parse('scalerunner://invite/ABC23')),
          'ABC23');
      expect(
          inviteCodeFromUri(Uri.parse('https://evil.com/invite/ABC23')),
          isNull);
      expect(
          inviteCodeFromUri(
              Uri.parse('https://scalerunner.c1gnus.com/other/ABC23')),
          isNull);
      expect(inviteCodeFromUri(Uri.parse('https://scalerunner.c1gnus.com/')),
          isNull);
    });

    test('WeeklyStat.withSession sets the weekday bit and accuracy', () {
      final w0 = WeeklyStat.empty(DateTime(2026, 7, 20)); // Monday
      expect(w0.daysPracticed, 0);
      expect(w0.accuracy, isNull);
      final w1 = w0.withSession(DateTime(2026, 7, 20), 10, 7);
      expect(w1.daysPracticed, 1);
      expect(w1.sessions, 1);
      expect(w1.accuracy, closeTo(0.7, 1e-9));
      final w2 = w1.withSession(DateTime(2026, 7, 20), 2, 2);
      expect(w2.daysPracticed, 1); // same day
      final w3 = w2.withSession(DateTime(2026, 7, 21), 1, 1);
      expect(w3.daysPracticed, 2);
    });

    test('WeeklyStat encode/decode roundtrips', () {
      final w = WeeklyStat.empty(DateTime(2026, 7, 20))
          .withSession(DateTime(2026, 7, 22), 9, 6);
      final r = WeeklyStat.decode(w.encode())!;
      expect(r.isoWeek, w.isoWeek);
      expect(r.daysMask, w.daysMask);
      expect(r.sessions, 1);
      expect(r.attempts, 9);
      expect(r.correct, 6);
      expect(WeeklyStat.decode(null), isNull);
      expect(WeeklyStat.decode('garbage'), isNull);
    });

    test('isoWeekOf / weekStartOf basics', () {
      expect(weekStartOf(DateTime(2026, 7, 22)), DateTime(2026, 7, 20));
      expect(isoWeekOf(DateTime(2026, 7, 20)),
          isoWeekOf(DateTime(2026, 7, 26)));
    });
  });
}
