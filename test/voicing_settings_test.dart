import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:scale_runner/quiz/quiz_settings.dart';
import 'package:scale_runner/social/social_models.dart';
import 'package:scale_runner/theory/voicings.dart';

VoicingSpec spec(String id, String name, List<int> offsets, {int rootPc = 0}) =>
    VoicingSpec(
      id: id,
      name: name,
      rootPc: rootPc,
      offsets: offsets,
      createdAt: DateTime.utc(2026),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late QuizSettings settings;

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    settings = await QuizSettings.load();
  });

  group('saved voicings', () {
    test('a fresh install has none', () async {
      expect(await settings.savedVoicings(), isEmpty);
    });

    test('round-trips a negative-offset shape', () async {
      await settings.upsertVoicing(spec('a', 'Drop 2', [-1, 4, 7, 12]));
      final saved = await settings.savedVoicings();
      expect(saved.length, 1);
      expect(saved.single.name, 'Drop 2');
      expect(saved.single.offsets, [-1, 4, 7, 12]);
      expect(saved.single.formula, '7-3-5-1');
    });

    test('keeps insertion order', () async {
      await settings.upsertVoicing(spec('a', 'First', [0, 4, 7]));
      await settings.upsertVoicing(spec('b', 'Second', [0, 3, 7]));
      await settings.upsertVoicing(spec('c', 'Third', [0, 7, 16]));
      expect(
        [for (final v in await settings.savedVoicings()) v.name],
        ['First', 'Second', 'Third'],
      );
    });

    test('upserting an existing id replaces it in place', () async {
      await settings.upsertVoicing(spec('a', 'First', [0, 4, 7]));
      await settings.upsertVoicing(spec('b', 'Second', [0, 3, 7]));
      await settings.upsertVoicing(spec('a', 'Renamed', [0, 4, 7]));
      final saved = await settings.savedVoicings();
      expect(saved.length, 2);
      expect([for (final v in saved) v.name], ['Renamed', 'Second']);
    });

    test('deleting removes only that voicing', () async {
      await settings.upsertVoicing(spec('a', 'First', [0, 4, 7]));
      await settings.upsertVoicing(spec('b', 'Second', [0, 3, 7]));
      await settings.deleteVoicing('a');
      expect(
        [for (final v in await settings.savedVoicings()) v.id],
        ['b'],
      );
    });

    test('deleting something that is not there is harmless', () async {
      await settings.upsertVoicing(spec('a', 'First', [0, 4, 7]));
      await settings.deleteVoicing('nope');
      expect((await settings.savedVoicings()).length, 1);
    });

    test('names with delimiters and unicode survive storage', () async {
      await settings.upsertVoicing(spec('a', 'a|b "c" Ré ♭9', [0, 4, 7]));
      expect((await settings.savedVoicings()).single.name, 'a|b "c" Ré ♭9');
    });

    test('reordering round-trips through storage', () async {
      await settings.upsertVoicing(spec('a', 'First', [0, 4, 7]));
      await settings.upsertVoicing(spec('b', 'Second', [0, 3, 7]));
      await settings.upsertVoicing(spec('c', 'Third', [0, 7, 16]));
      final all = await settings.savedVoicings();
      await settings.reorderVoicings([all[2], all[0], all[1]]);
      expect(
        [for (final v in await settings.savedVoicings()) v.name],
        ['Third', 'First', 'Second'],
      );
    });

    test('an edit after a reorder keeps the new position', () async {
      await settings.upsertVoicing(spec('a', 'First', [0, 4, 7]));
      await settings.upsertVoicing(spec('b', 'Second', [0, 3, 7]));
      final all = await settings.savedVoicings();
      await settings.reorderVoicings([all[1], all[0]]);
      await settings.upsertVoicing(spec('a', 'Renamed', [0, 4, 7]));
      expect(
        [for (final v in await settings.savedVoicings()) v.name],
        ['Second', 'Renamed'],
      );
    });

    test('a delete after a reorder keeps the rest in order', () async {
      await settings.upsertVoicing(spec('a', 'First', [0, 4, 7]));
      await settings.upsertVoicing(spec('b', 'Second', [0, 3, 7]));
      await settings.upsertVoicing(spec('c', 'Third', [0, 7, 16]));
      final all = await settings.savedVoicings();
      await settings.reorderVoicings([all[2], all[1], all[0]]);
      await settings.deleteVoicing('b');
      expect(
        [for (final v in await settings.savedVoicings()) v.id],
        ['c', 'a'],
      );
    });

    test('the free limit is 3', () {
      expect(QuizSettings.freeVoicingLimit, 3);
    });
  });

  group('drill settings', () {
    test('defaults: C, chromatic, dots and formula on', () async {
      expect(await settings.voicingStartKeyPc(), 0);
      expect(await settings.voicingIncrement(), KeyIncrement.chromatic);
      expect(await settings.voicingShowDots(), isTrue);
      expect(await settings.voicingShowFormula(), isTrue);
    });

    test('start key wraps into 0–11', () async {
      await settings.setVoicingStartKeyPc(14);
      expect(await settings.voicingStartKeyPc(), 2);
    });

    test('increment persists both ways', () async {
      await settings.setVoicingIncrement(KeyIncrement.fifths);
      expect(await settings.voicingIncrement(), KeyIncrement.fifths);
      await settings.setVoicingIncrement(KeyIncrement.chromatic);
      expect(await settings.voicingIncrement(), KeyIncrement.chromatic);
    });

    test('hints toggle off and back on', () async {
      await settings.setVoicingShowDots(false);
      await settings.setVoicingShowFormula(false);
      expect(await settings.voicingShowDots(), isFalse);
      expect(await settings.voicingShowFormula(), isFalse);
      await settings.setVoicingShowDots(true);
      expect(await settings.voicingShowDots(), isTrue);
    });
  });

  group('Voicings never touches scoring', () {
    test('saving and drilling leaves every lifetime stat empty', () async {
      await settings.upsertVoicing(spec('a', 'Drop 2', [-1, 4, 7, 12]));
      expect(await settings.runKeyStats(), isEmpty);
      expect(await settings.jamQualityStats(), isEmpty);
      expect(await settings.invChordStats(), isEmpty);
      final modes = await settings.modeStats();
      expect(modes.runAttempts, 0);
      expect(modes.jamAttempts, 0);
      expect(modes.invAttempts, 0);
    });
  });

  group('voicing folders', () {
    test('a fresh install has none, and nothing is expanded-or-not yet', () async {
      expect(await settings.voicingFolders(), isEmpty);
      expect(await settings.expandedVoicingFolders(), isNull);
    });

    test('upsert adds, then renames in place', () async {
      final f = VoicingFolder.create('Ballads');
      await settings.upsertVoicingFolder(f);
      await settings.upsertVoicingFolder(f.renamed('Standards'));
      final all = await settings.voicingFolders();
      expect(all.length, 1);
      expect(all.single.name, 'Standards');
      expect(all.single.id, f.id);
    });

    test('deleting a folder frees its voicings instead of deleting them',
        () async {
      final f = VoicingFolder.create('Ballads');
      await settings.upsertVoicingFolder(f);
      await settings.upsertVoicing(
          spec('a', 'In it', [0, 4, 7]).copyWith(folderId: f.id));
      await settings.upsertVoicing(spec('b', 'Loose', [0, 3, 7]));

      await settings.deleteVoicingFolder(f.id);

      expect(await settings.voicingFolders(), isEmpty);
      final saved = await settings.savedVoicings();
      expect(saved.length, 2); // nothing lost
      expect(saved.every((v) => v.folderId == null), isTrue);
    });

    test('reorder rewrites display order', () async {
      final a = VoicingFolder.create('A');
      final b = VoicingFolder.create('B');
      await settings.upsertVoicingFolder(a);
      await settings.upsertVoicingFolder(b);
      await settings.reorderVoicingFolders([b, a]);
      expect((await settings.voicingFolders()).map((f) => f.name), ['B', 'A']);
    });

    test('expansion state round-trips', () async {
      await settings.setExpandedVoicingFolders({'f1', 'f2'});
      expect(await settings.expandedVoicingFolders(), {'f1', 'f2'});
      await settings.setExpandedVoicingFolders({});
      expect(await settings.expandedVoicingFolders(), isEmpty); // not null
    });
  });

  group('voicing tags', () {
    test('renaming a tag needs no change to the voicings carrying it',
        () async {
      final t = VoicingTag.create('drop2', prefix: 't');
      await settings.upsertVoicingTag(t);
      await settings
          .upsertVoicing(spec('a', 'Tagged', [0, 4, 7]).copyWith(tagIds: [t.id]));

      await settings.upsertVoicingTag(t.renamed('Drop 2'));

      expect((await settings.voicingTags()).single.name, 'Drop 2');
      expect((await settings.savedVoicings()).single.tagIds, [t.id]);
    });

    test('deleting a tag strips it from every voicing', () async {
      final keep = VoicingTag.create('keep', prefix: 't');
      final drop = VoicingTag.create('drop', prefix: 't');
      await settings.upsertVoicingTag(keep);
      await settings.upsertVoicingTag(drop);
      await settings.upsertVoicing(spec('a', 'Both', [0, 4, 7])
          .copyWith(tagIds: [keep.id, drop.id]));
      await settings.upsertVoicing(
          spec('b', 'Neither', [0, 3, 7]));

      await settings.deleteVoicingTag(drop.id);

      expect((await settings.voicingTags()).single.id, keep.id);
      final saved = await settings.savedVoicings();
      expect(saved.first.tagIds, [keep.id]);
      expect(saved.last.tagIds, isEmpty);
    });
  });

  // The drill screen ends a session with `recordWeeklySession(0, 0)`. These
  // pin down why that one call is what makes "counts as practice, never
  // scored" work without a single change to the social layer.
  group('a Voicings session counts as practice but is never scored', () {
    final monday = DateTime(2026, 8, 10);

    test('marks the day and the session, but not accuracy', () {
      final after = WeeklyStat.empty(monday).withSession(monday, 0, 0);
      expect(after.sessions, 1);
      expect(after.daysPracticed, 1);
      expect(after.attempts, 0);
      expect(after.correct, 0);
      // Null, not 0%. A week of nothing but Voicings has no accuracy to show,
      // which is a different thing from having practised badly.
      expect(after.accuracy, isNull);
    });

    test('cannot dilute an accuracy earned in a scored mode', () {
      final scored = WeeklyStat.empty(monday).withSession(monday, 10, 8);
      final plusVoicings = scored.withSession(monday, 0, 0);
      expect(plusVoicings.accuracy, scored.accuracy);
      expect(plusVoicings.attempts, scored.attempts);
      expect(plusVoicings.sessions, 2); // the practice still counts
    });
  });

  group('sync-ready records', () {
    test('a line saved before sync reads updatedAt = createdAt, pos = index',
        () async {
      // Two legacy lines: no `up`, no `pos`.
      await settings.upsertVoicing(spec('a', 'A', [0, 4, 7]));
      final prefs = SharedPreferencesAsync();
      await prefs.setStringList('voicing_customs', [
        '{"id":"a","name":"A","root":0,"offsets":[0,4,7],"at":1000}',
        '{"id":"b","name":"B","root":0,"offsets":[0,3,7],"at":2000}',
      ]);
      final saved = await settings.savedVoicings();
      expect(saved.map((v) => v.position), [0.0, 1.0]);
      expect(saved[0].updatedAt, saved[0].createdAt);
      expect(saved[1].updatedAt, DateTime.fromMicrosecondsSinceEpoch(2000));
    });

    test('upsert stamps updatedAt and appends after the last position',
        () async {
      final before = DateTime.now();
      await settings.upsertVoicing(spec('a', 'A', [0, 4, 7]));
      await settings.upsertVoicing(spec('b', 'B', [0, 3, 7]));
      final saved = await settings.savedVoicings();
      expect(saved[0].updatedAt.isBefore(before), isFalse);
      expect(saved[1].position, greaterThan(saved[0].position));

      // An edit keeps its position and bumps updatedAt.
      await Future<void>.delayed(const Duration(milliseconds: 2));
      await settings.upsertVoicing(saved[0].copyWith(name: 'A2'));
      final again = await settings.savedVoicings();
      expect(again[0].position, saved[0].position);
      expect(again[0].updatedAt.isAfter(saved[0].updatedAt), isTrue);
    });

    test('reorder keeps positions ascending and only touches movers',
        () async {
      for (final id in ['a', 'b', 'c', 'd']) {
        await settings.upsertVoicing(spec(id, id, [0, 4, 7]));
      }
      final saved = await settings.savedVoicings(); // a b c d
      await Future<void>.delayed(const Duration(milliseconds: 2));
      // Move d to the front.
      await settings.reorderVoicings([saved[3], ...saved.take(3)]);
      final after = await settings.savedVoicings();
      expect(after.map((v) => v.id), ['d', 'a', 'b', 'c']);
      for (var i = 1; i < after.length; i++) {
        expect(after[i].position, greaterThan(after[i - 1].position));
      }
      final movedD = after[0];
      expect(movedD.updatedAt.isAfter(saved[3].updatedAt), isTrue);
      // a, b, c kept their positions and timestamps.
      for (var i = 0; i < 3; i++) {
        expect(after[i + 1].position, saved[i].position);
        expect(after[i + 1].updatedAt, saved[i].updatedAt);
      }
    });

    test('deletes leave a tombstone until pruned', () async {
      await settings.upsertVoicing(spec('a', 'A', [0, 4, 7]));
      await settings.upsertVoicingFolder(VoicingFolder.create('Blues'));
      final folder = (await settings.voicingFolders()).single;
      await settings.deleteVoicing('a');
      await settings.deleteVoicingFolder(folder.id);
      final gone = await settings.deletedRecords();
      expect(gone.map((d) => (d.id, d.kind)),
          [('a', 'voicing'), (folder.id, 'folder')]);
      await settings.pruneDeletedRecords(['a']);
      expect((await settings.deletedRecords()).map((d) => d.id), [folder.id]);
    });

    test('labels get positions and updatedAt too', () async {
      await settings.upsertVoicingTag(VoicingTag.create('x', prefix: 't'));
      await settings.upsertVoicingTag(VoicingTag.create('y', prefix: 't'));
      final tags = await settings.voicingTags();
      expect(tags[1].position, greaterThan(tags[0].position));
      expect(tags[0].updatedAt.year, greaterThan(2000));
      // Legacy label line: no up/pos.
      await SharedPreferencesAsync()
          .setStringList('voicing_folders', ['{"id":"f1","name":"Old"}']);
      final old = (await settings.voicingFolders()).single;
      expect(old.position, 0);
      expect(old.updatedAt.microsecondsSinceEpoch, 0);
    });

    test('deviceId is minted once and then stable', () async {
      final a = await settings.deviceId();
      expect(a, hasLength(32));
      expect(await settings.deviceId(), a);
    });
  });
}
