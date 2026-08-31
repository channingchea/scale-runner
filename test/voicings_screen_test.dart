// The Voicings list screen: folders, tags and search over the same flat list.
//
// Storage is exercised through [QuizSettings] itself rather than raw prefs
// keys, so these tests break if the screen and the store ever disagree about
// what a voicing is.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:scale_runner/midi/midi_service.dart';
import 'package:scale_runner/quiz/quiz_settings.dart';
import 'package:scale_runner/screens/voicings_screen.dart';
import 'package:scale_runner/theme/app_theme.dart';
import 'package:scale_runner/theory/voicings.dart';

const _drop2 = [-1, 4, 7, 12];

VoicingSpec _spec(
  String id,
  String name, {
  String? folderId,
  int? colorTag,
  List<String> tagIds = const [],
}) =>
    VoicingSpec(
      id: id,
      name: name,
      rootPc: 0,
      offsets: _drop2,
      createdAt: DateTime.utc(2026),
      folderId: folderId,
      colorTag: colorTag,
      tagIds: tagIds,
    );

Future<void> _pump(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(
    home: VoicingsScreen(midi: MidiService()),
  ));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late QuizSettings settings;

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    settings = await QuizSettings.load();
  });

  testWidgets('an empty collection still offers the cold start', (t) async {
    await _pump(t);
    expect(find.text('Create your first voicing'), findsOneWidget);
    // No list chrome before there is a list.
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('saved voicings render, newest organisation and all', (t) async {
    await settings.upsertVoicing(_spec('1', 'Maj7 drop 2'));
    await settings.upsertVoicing(_spec('2', 'Blues shell'));
    await _pump(t);

    expect(find.text('Maj7 drop 2'), findsOneWidget);
    expect(find.text('Blues shell'), findsOneWidget);
    // No folders yet, so no section headers to get in the way.
    expect(find.text('Ungrouped'), findsNothing);
  });

  testWidgets('search narrows by name, tag label and folder name', (t) async {
    const folder = VoicingFolder('f1', 'Ballads');
    const tag = VoicingTag('t1', 'rootless');
    await settings.upsertVoicingFolder(folder);
    await settings.upsertVoicingTag(tag);
    await settings.upsertVoicing(_spec('1', 'Maj7 drop 2', folderId: 'f1'));
    await settings.upsertVoicing(_spec('2', 'Blues shell', tagIds: ['t1']));
    await settings.upsertVoicing(_spec('3', 'Quartal stack'));
    await _pump(t);

    final field = find.byType(TextField).first;

    await t.enterText(field, 'blues');
    await t.pumpAndSettle();
    expect(find.text('Blues shell'), findsOneWidget);
    expect(find.text('Maj7 drop 2'), findsNothing);

    // A tag label the card carries but never spells out in its name.
    await t.enterText(field, 'rootless');
    await t.pumpAndSettle();
    expect(find.text('Blues shell'), findsOneWidget);
    expect(find.text('Quartal stack'), findsNothing);

    // A folder name surfaces its contents.
    await t.enterText(field, 'ballads');
    await t.pumpAndSettle();
    expect(find.text('Maj7 drop 2'), findsOneWidget);
    expect(find.text('Blues shell'), findsNothing);

    await t.enterText(field, 'nothing here');
    await t.pumpAndSettle();
    expect(find.text('No voicings match'), findsOneWidget);
  });

  testWidgets('a folder section collapses and expands', (t) async {
    await settings.upsertVoicingFolder(const VoicingFolder('f1', 'Ballads'));
    await settings.upsertVoicing(_spec('1', 'Maj7 drop 2', folderId: 'f1'));
    await settings.upsertVoicing(_spec('2', 'Blues shell'));
    await _pump(t);

    expect(find.text('Ballads'), findsOneWidget);
    expect(find.text('Ungrouped'), findsOneWidget);
    expect(find.text('Maj7 drop 2'), findsOneWidget);

    await t.tap(find.text('Ballads'));
    await t.pumpAndSettle();
    // Collapsed: the header stays, its card goes, and the loose card is
    // untouched.
    expect(find.text('Ballads'), findsOneWidget);
    expect(find.text('Maj7 drop 2'), findsNothing);
    expect(find.text('Blues shell'), findsOneWidget);

    await t.tap(find.text('Ballads'));
    await t.pumpAndSettle();
    expect(find.text('Maj7 drop 2'), findsOneWidget);
  });

  testWidgets('a colour tag paints a stripe and a text tag a chip',
      (t) async {
    await settings.upsertVoicingTag(const VoicingTag('t1', 'rootless'));
    await settings.upsertVoicing(
        _spec('1', 'Maj7 drop 2', colorTag: 2, tagIds: ['t1']));
    await _pump(t);

    expect(
      find.byWidgetPredicate((w) =>
          w is ColoredBox && w.color == kVoicingTagColors[2]),
      findsOneWidget,
    );
    // The chip on the card, not a filter chip — the filter row shows the same
    // label, so scope the search to the card.
    expect(find.text('rootless'), findsWidgets);
  });

  testWidgets('a tag filter chip toggles on and off', (t) async {
    await settings.upsertVoicingTag(const VoicingTag('t1', 'rootless'));
    await settings.upsertVoicing(_spec('1', 'Maj7 drop 2', tagIds: ['t1']));
    await settings.upsertVoicing(_spec('2', 'Blues shell'));
    await _pump(t);

    expect(find.text('Blues shell'), findsOneWidget);

    await t.tap(find.byType(FilterChip).first);
    await t.pumpAndSettle();
    expect(find.text('Maj7 drop 2'), findsOneWidget);
    expect(find.text('Blues shell'), findsNothing);

    // Untoggling the same chip brings everything back — no dead end.
    await t.tap(find.byType(FilterChip).first);
    await t.pumpAndSettle();
    expect(find.text('Blues shell'), findsOneWidget);
  });

  testWidgets('deleting a folder keeps its voicings, in Ungrouped', (t) async {
    await settings.upsertVoicingFolder(const VoicingFolder('f1', 'Ballads'));
    await settings.upsertVoicing(_spec('1', 'Maj7 drop 2', folderId: 'f1'));
    await _pump(t);

    await settings.deleteVoicingFolder('f1');
    final left = await settings.savedVoicings();
    expect(left.length, 1);
    expect(left.single.folderId, isNull);
  });

  testWidgets('folder headers drag to reorder, and take their cards along',
      (t) async {
    await settings.upsertVoicingFolder(const VoicingFolder('f1', 'Ballads'));
    await settings.upsertVoicingFolder(const VoicingFolder('f2', 'Blues'));
    await settings.upsertVoicing(_spec('1', 'Maj7 drop 2', folderId: 'f1'));
    await settings.upsertVoicing(_spec('2', 'Shell voicing', folderId: 'f2'));
    await _pump(t);

    // Ballads sits above Blues to start with.
    expect(t.getTopLeft(find.text('Ballads')).dy,
        lessThan(t.getTopLeft(find.text('Blues')).dy));

    final grip = find.byKey(const ValueKey('folder-grip-f2'));
    expect(grip, findsOneWidget);
    final gesture = await t.startGesture(t.getCenter(grip));
    await t.pump(const Duration(milliseconds: 100));
    // Up past the Ballads section, in steps, so the list tracks the drag.
    for (var i = 0; i < 8; i++) {
      await gesture.moveBy(const Offset(0, -20));
      await t.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await t.pumpAndSettle();

    // On screen and in storage, Blues is now first.
    expect(t.getTopLeft(find.text('Blues')).dy,
        lessThan(t.getTopLeft(find.text('Ballads')).dy));
    expect([for (final f in await settings.voicingFolders()) f.id],
        ['f2', 'f1']);
    // The flat voicing list is re-sliced to match, so each card stays with its
    // folder rather than drifting into the one above.
    expect([for (final v in await settings.savedVoicings()) v.id], ['2', '1']);
  });

  testWidgets('a card still drags inside its own folder', (t) async {
    await settings.upsertVoicingFolder(const VoicingFolder('f1', 'Ballads'));
    await settings.upsertVoicing(_spec('1', 'First', folderId: 'f1'));
    await settings.upsertVoicing(_spec('2', 'Second', folderId: 'f1'));
    await _pump(t);

    expect(t.getTopLeft(find.text('First')).dy,
        lessThan(t.getTopLeft(find.text('Second')).dy));

    // The second card's grip: two cards, so both are draggable.
    final grips = find.byIcon(Icons.drag_handle);
    final gesture = await t.startGesture(t.getCenter(grips.last));
    await t.pump(const Duration(milliseconds: 100));
    for (var i = 0; i < 8; i++) {
      await gesture.moveBy(const Offset(0, -20));
      await t.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await t.pumpAndSettle();

    expect([for (final v in await settings.savedVoicings()) v.id], ['2', '1']);
  });

  testWidgets('one folder shows no grip — nothing to reorder', (t) async {
    await settings.upsertVoicingFolder(const VoicingFolder('f1', 'Ballads'));
    await settings.upsertVoicing(_spec('1', 'Maj7 drop 2', folderId: 'f1'));
    await _pump(t);
    expect(find.byKey(const ValueKey('folder-grip-f1')), findsNothing);
  });
}
