import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:scale_runner/quiz/quiz_controller.dart' show QuizMode;
import 'package:scale_runner/quiz/quiz_settings.dart';
import 'package:scale_runner/streak/streak_service.dart';
import 'package:scale_runner/sync/mock_sync_backend.dart';
import 'package:scale_runner/sync/sync_service.dart';
import 'package:scale_runner/theory/voicings.dart';

/// One phone: its own prefs store, its own backend handle on the shared
/// server, its own SyncService. [run] makes its store the live one, so only
/// one device may be mid-operation at a time (the tests are sequential).
class Device {
  Device(MockSyncServer server) {
    SharedPreferencesAsyncPlatform.instance = store;
    backend = MockSyncBackend(server);
    streak = StreakService(isPro: () => false);
    sync = SyncService(backend: backend, streak: streak, retryDelays: []);
  }

  final store = InMemorySharedPreferencesAsync.empty();
  late final MockSyncBackend backend;
  late final StreakService streak;
  late final SyncService sync;
  QuizSettings? _settings;

  Future<T> run<T>(Future<T> Function(QuizSettings s) body) async {
    SharedPreferencesAsyncPlatform.instance = store;
    return body(_settings ??= await QuizSettings.load());
  }

  Future<void> doSync() => run((_) => sync.sync());
  Future<List<VoicingSpec>> voicings() => run((s) => s.savedVoicings());
  Future<List<VoicingFolder>> folders() => run((s) => s.voicingFolders());
  Future<List<VoicingTag>> tags() => run((s) => s.voicingTags());
}

VoicingSpec spec(String id, String name, [List<int> offsets = const [0, 4, 7]]) =>
    VoicingSpec(
      id: id,
      name: name,
      rootPc: 0,
      offsets: offsets,
      createdAt: DateTime.utc(2026),
    );

Future<void> tick() => Future<void>.delayed(const Duration(milliseconds: 2));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockSyncServer server;
  late Device a, b;

  setUp(() {
    server = MockSyncServer();
    a = Device(server);
    b = Device(server);
    // Each SyncService installed itself here; the tests drive sync directly.
    QuizSettings.onSyncedDataChanged = null;
  });

  test('a voicing saved on A shows up on B', () async {
    await a.run((s) => s.upsertVoicing(spec('v1', 'Drop 2', [-1, 4, 7, 12])));
    await a.doSync();
    await b.doSync();
    final got = (await b.voicings()).single;
    expect(got.name, 'Drop 2');
    expect(got.offsets, [-1, 4, 7, 12]);
    expect(got.position, (await a.voicings()).single.position);
    expect(a.sync.state, SyncState.idle);
    expect(b.sync.lastSyncedAt, isNotNull);
  });

  test('first sign-in on both devices is a union', () async {
    await a.run((s) => s.upsertVoicing(spec('x', 'X')));
    await b.run((s) => s.upsertVoicing(spec('y', 'Y')));
    await a.doSync();
    await b.doSync();
    await a.doSync();
    expect((await a.voicings()).map((v) => v.id), ['x', 'y']);
    expect((await b.voicings()).map((v) => v.id), ['x', 'y']);
  });

  test('the same voicing edited on both while offline: newer wins', () async {
    await a.run((s) => s.upsertVoicing(spec('v', 'Original')));
    await a.doSync();
    await b.doSync();
    // A renames first, B renames later; neither syncs until both are done.
    await a.run((s) async =>
        s.upsertVoicing((await s.savedVoicings()).single.copyWith(name: 'A')));
    await tick();
    await b.run((s) async =>
        s.upsertVoicing((await s.savedVoicings()).single.copyWith(name: 'B')));
    await a.doSync();
    await b.doSync(); // B's copy is newer: it wins and is pushed
    await a.doSync();
    expect((await a.voicings()).single.name, 'B');
    expect((await b.voicings()).single.name, 'B');
  });

  test('a delete on A reaches B and does not come back', () async {
    await a.run((s) => s.upsertVoicing(spec('v', 'V')));
    await a.doSync();
    await b.doSync();
    await a.run((s) => s.deleteVoicing('v'));
    await a.doSync();
    expect(await a.run((s) => s.deletedRecords()), isEmpty); // pruned
    await b.doSync();
    expect(await b.voicings(), isEmpty);
    await b.doSync();
    await a.doSync();
    expect(await a.voicings(), isEmpty);
  });

  test('an edit made after a delete brings the voicing back', () async {
    await a.run((s) => s.upsertVoicing(spec('v', 'V')));
    await a.doSync();
    await b.doSync();
    await a.run((s) => s.deleteVoicing('v'));
    await tick();
    await b.run((s) async =>
        s.upsertVoicing((await s.savedVoicings()).single.copyWith(name: 'V2')));
    await b.doSync();
    await a.doSync();
    expect((await a.voicings()).single.name, 'V2');
  });

  test('a reorder on A shows on B, with A\'s positions', () async {
    for (final id in ['p', 'q', 'r']) {
      await a.run((s) => s.upsertVoicing(spec(id, id)));
    }
    await a.doSync();
    await b.doSync();
    await a.run((s) async {
      final v = await s.savedVoicings();
      await s.reorderVoicings([v[2], v[0], v[1]]);
    });
    await a.doSync();
    await b.doSync();
    expect((await b.voicings()).map((v) => v.id), ['r', 'p', 'q']);
  });

  test('folders and tags sync, and a folder delete unfiles on B', () async {
    await a.run((s) async {
      await s.upsertVoicingFolder(VoicingFolder.create('Blues'));
      await s.upsertVoicingTag(VoicingTag.create('rootless', prefix: 't'));
      final f = (await s.voicingFolders()).single;
      final t = (await s.voicingTags()).single;
      await s.upsertVoicing(
          spec('v', 'V').copyWith(folderId: f.id, tagIds: [t.id]));
    });
    await a.doSync();
    await b.doSync();
    expect((await b.folders()).single.name, 'Blues');
    expect((await b.tags()).single.name, 'rootless');
    expect((await b.voicings()).single.folderId, isNotNull);

    await tick();
    await a.run((s) async =>
        s.deleteVoicingFolder((await s.voicingFolders()).single.id));
    await a.doSync();
    await b.doSync();
    expect(await b.folders(), isEmpty);
    expect((await b.voicings()).single.folderId, isNull);
  });

  test('offline: nothing is lost, state waits, next sync catches up', () async {
    await a.run((s) => s.upsertVoicing(spec('v', 'V')));
    a.backend.offline = true;
    await a.doSync();
    expect(a.sync.state, SyncState.waiting);
    expect(server.library, isEmpty);
    expect((await a.voicings()).single.name, 'V');
    a.backend.offline = false;
    await a.doSync();
    expect(a.sync.state, SyncState.idle);
    expect(server.library.keys, ['v']);
  });

  test('signed out, sync is a no-op', () async {
    await a.run((s) => s.upsertVoicing(spec('v', 'V')));
    a.backend.signedIn = false;
    await a.doSync();
    expect(a.backend.pulls, 0);
    expect(server.library, isEmpty);
  });

  test('a clean second sync pushes and pulls nothing new', () async {
    await a.run((s) => s.upsertVoicing(spec('v', 'V')));
    await a.doSync();
    final pushes = a.backend.pushes;
    await a.doSync();
    expect(a.backend.pushes, pushes);
    expect(a.sync.libraryChanged, isFalse);
  });

  test('sign-out clears the last-synced stamp and stops nothing else',
      () async {
    await a.run((s) => s.upsertVoicing(spec('v', 'V')));
    await a.doSync();
    expect(a.sync.lastSyncedAt, isNotNull);
    await a.run((_) => a.sync.onSignedOut());
    expect(a.sync.lastSyncedAt, isNull);
    expect(await a.run((s) => s.syncLastAt()), isNull);
    expect((await a.voicings()).single.name, 'V');
  });

  group('practice settings', () {
    test('a setting changed on A shows on B; different keys both survive',
        () async {
      await a.run((s) => s.setJamKeyPc(9));
      await b.run((s) => s.setRunRepsPerKey(4));
      await a.doSync();
      await b.doSync();
      await a.doSync();
      expect(await a.run((s) => s.jamKeyPc()), 9);
      expect(await a.run((s) => s.runRepsPerKey()), 4);
      expect(await b.run((s) => s.jamKeyPc()), 9);
      expect(await b.run((s) => s.runRepsPerKey()), 4);
    });

    test('the same key changed on both: newer wins', () async {
      await a.run((s) => s.setJamKeyPc(2));
      await tick();
      await b.run((s) => s.setJamKeyPc(7));
      await a.doSync();
      await b.doSync();
      await a.doSync();
      expect(await a.run((s) => s.jamKeyPc()), 7);
    });

    test('a list setting round-trips and an unstamped legacy value yields',
        () async {
      await a.run((s) => s.setEnabledNames(QuizMode.scale, {'Major'}));
      await a.doSync();
      // B set this before sync existed: no stamp, so A's synced copy wins.
      await b.run((s) => s.setEnabledNames(QuizMode.scale, {'Minor'}));
      await b.run((s) => SharedPreferencesAsync().remove('enabled_scales_updated_at'));
      await b.doSync();
      expect(await b.run((s) => s.enabledNames(QuizMode.scale)), {'Major'});
    });

    test('applying a remote value does not re-trigger a push', () async {
      await a.run((s) => s.setJamKeyPc(4));
      await a.doSync();
      await b.doSync();
      final pushes = server.settings['jam_key']!.updatedAt;
      await b.doSync();
      expect(server.settings['jam_key']!.updatedAt, pushes);
    });
  });

  group('stats buckets', () {
    test('counters sum across devices; a reset clears only this device',
        () async {
      await a.run((s) => s.mergeRunStats({'C Major': (10, 8)}, {'Ionian': (10, 8)}));
      await b.run((s) => s.mergeRunStats(
          {'C Major': (5, 5), 'G Major': (2, 1)}, {'Ionian': (7, 6)}));
      await a.doSync();
      await b.doSync();
      await a.doSync();
      expect(await a.run((s) => s.runKeyStats()),
          {'C Major': (15, 13), 'G Major': (2, 1)});
      expect(await b.run((s) => s.runKeyStats()),
          {'C Major': (15, 13), 'G Major': (2, 1)});
      expect((await a.run((s) => s.modeStats())).runAttempts, 17);

      await a.run((s) => s.resetRunStats());
      await a.doSync();
      await b.doSync();
      expect(await a.run((s) => s.runKeyStats()),
          {'C Major': (5, 5), 'G Major': (2, 1)});
      expect(await b.run((s) => s.runKeyStats()),
          {'C Major': (5, 5), 'G Major': (2, 1)});
    });

    test('a session merges into this device only, never the cached buckets',
        () async {
      await a.run((s) => s.mergeInversionStats({'Major': (4, 4)}));
      await a.doSync();
      await b.doSync();
      await b.run((s) => s.mergeInversionStats({'Major': (1, 0)}));
      await b.doSync();
      await a.doSync();
      expect(await a.run((s) => s.invChordStats()), {'Major': (5, 4)});
      expect(await b.run((s) => s.invChordStats()), {'Major': (5, 4)});
      // Repeated syncs don't inflate anything.
      await b.doSync();
      await a.doSync();
      expect(await a.run((s) => s.invChordStats()), {'Major': (5, 4)});
    });

    test('quiz score sums, best streak is the max', () async {
      for (var i = 0; i < 3; i++) {
        await a.run((s) => s.recordQuizWin(QuizMode.chord, i + 1));
      }
      await b.run((s) => s.recordQuizWin(QuizMode.chord, 9));
      await a.doSync();
      await b.doSync();
      await a.doSync();
      expect(await a.run((s) => s.quizScore(QuizMode.chord)), 4);
      expect(await b.run((s) => s.quizScore(QuizMode.chord)), 4);
      expect(await a.run((s) => s.quizBestStreak(QuizMode.chord)), 9);
      expect(await b.run((s) => s.quizScore(QuizMode.scale)), 0);
    });

    test('the daily streak follows the device that practiced last', () async {
      await a.run((_) => a.streak.init());
      await b.run((_) => b.streak.init());
      await a.run((_) => a.streak.recordPractice());
      expect(a.streak.currentStreak, 1);
      await a.doSync();
      await b.doSync();
      expect(b.streak.currentStreak, 1);
      expect(b.streak.totalPracticeDays, 1);
      expect(b.streak.practicedToday, isTrue);
      // B practicing today again is a no-op, and A's copy stays 1.
      await b.run((_) => b.streak.recordPractice());
      await b.doSync();
      await a.doSync();
      expect(a.streak.currentStreak, 1);
    });

    test('sign-out forgets the other devices\' buckets', () async {
      await b.run((s) => s.mergeRunStats({'C Major': (5, 5)}, {}));
      await b.doSync();
      await a.doSync();
      expect(await a.run((s) => s.runKeyStats()), {'C Major': (5, 5)});
      await a.run((_) => a.sync.onSignedOut());
      expect(await a.run((s) => s.runKeyStats()), isEmpty);
    });
  });
}
