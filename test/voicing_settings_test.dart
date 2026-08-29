import 'package:flutter_test/flutter_test.dart';
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
}
