import 'package:flutter_test/flutter_test.dart';
import 'package:scale_runner/theory/voicings.dart';

/// A spec with fixed id/date so tests stay deterministic.
VoicingSpec spec(List<int> offsets, {int rootPc = 0, String name = 'Test'}) =>
    VoicingSpec(
      id: 'test',
      name: name,
      rootPc: rootPc,
      offsets: offsets,
      createdAt: DateTime.fromMicrosecondsSinceEpoch(0),
    );

/// The three reference shapes the root rule was verified against.
const drop2 = [-1, 4, 7, 12]; // B3 E4 G4 C5 — Maj7 drop 2, 7th in bass
const openTriad = [0, 7, 16]; // C4 G4 E5
const rootlessA = [4, 7, 11, 14]; // E4 G4 B4 D5

void main() {
  group('rootMidiFor — the root rule', () {
    test('nearest occurrence above: B3 in C reads the root as C4', () {
      expect(rootMidiFor([59, 64, 67, 72], 0), 60);
    });
    test('lowest note is the root itself', () {
      expect(rootMidiFor([60, 67, 76], 0), 60);
    });
    test('rootless voicing still anchors to the nearest root', () {
      expect(rootMidiFor([64, 67, 71, 74], 0), 60);
    });
    test('input order does not matter', () {
      expect(rootMidiFor([72, 59, 67, 64], 0), 60);
    });
    test('7 semitones above picks the root above, not below', () {
      expect(rootMidiFor([67], 0), 72);
    });
    test('tritone tie resolves downward (bass offset +6, not -6)', () {
      expect(rootMidiFor([66], 0), 60);
    });
    test('works for a non-C root', () {
      expect(rootMidiFor([62, 66, 69], 2), 62); // D triad, D root
      expect(rootMidiFor([59, 64, 67, 72], 4), 64); // same notes read in E
    });
  });

  group('offsetsFrom — the three reference shapes', () {
    test('B3 E4 G4 C5 in C = Maj7 drop 2', () {
      expect(offsetsFrom([59, 64, 67, 72], 0), drop2);
    });
    test('C4 G4 E5 in C = open triad', () {
      expect(offsetsFrom([60, 67, 76], 0), openTriad);
    });
    test('E4 G4 B4 D5 in C = rootless A', () {
      expect(offsetsFrom([64, 67, 71, 74], 0), rootlessA);
    });
    test('offsets are register-independent', () {
      expect(offsetsFrom([71, 76, 79, 84], 0), drop2); // same shape, 8va
      expect(offsetsFrom([47, 52, 55, 60], 0), drop2); // same shape, 8vb
    });
    test('offsets are key-independent', () {
      expect(offsetsFrom([64, 69, 72, 77], 5), drop2); // the drop 2 in F
    });
    test('empty input yields no offsets', () {
      expect(offsetsFrom([], 0), isEmpty);
    });
  });

  group('VoicingSpec — derived views', () {
    final s = spec(drop2);
    test('sig re-bases the bass to 0', () => expect(s.sig, [0, 5, 8, 13]));
    test('span is bass to top', () => expect(s.span, 13));
    test('noteCount', () => expect(s.noteCount, 4));
    test('sig equals offsets when the root is already the bass', () {
      expect(spec(openTriad).sig, openTriad);
    });
    test('bassPcIn transposes the bass tone, negative offsets included', () {
      expect(s.bassPcIn(0), 11); // C: the 7th, B
      expect(s.bassPcIn(5), 4); // F: the 7th, E
      expect(s.bassPcIn(1), 0); // Db: the 7th, C
      expect(spec(openTriad).bassPcIn(7), 7); // root in the bass
    });
    test('notesFrom rebuilds the played shape', () {
      expect(s.notesFrom(60), [59, 64, 67, 72]);
      expect(spec(rootlessA).notesFrom(60), [64, 67, 71, 74]);
    });
    test('rootName and formula', () {
      expect(s.rootName, 'C');
      expect(s.formula, '7-3-5-1');
    });
  });

  group('voicingFormula — degree spelling from offsets', () {
    test('the plan spot-checks', () {
      expect(voicingFormula(drop2), '7-3-5-1');
      expect(voicingFormula(openTriad), '1-5-3');
      expect(voicingFormula(rootlessA), '3-5-7-9');
      expect(voicingFormula([10, 14, 15, 19]), 'b7-9-b3-5'); // rootless B min9
      expect(voicingFormula([0, 5, 10, 15, 19]), '1-4-b7-b3-5'); // quartal
      expect(voicingFormula([0, 3, 6, 9]), '1-b3-b5-bb7'); // dim7
    });
    test('compound relabelling above the octave', () {
      expect(voicingFormula([0, 4, 7, 14]), '1-3-5-9');
      expect(voicingFormula([0, 4, 10, 13]), '1-3-b7-b9');
      expect(voicingFormula([0, 4, 7, 17]), '1-3-5-11');
      expect(voicingFormula([0, 4, 7, 18]), '1-3-5-#11');
      expect(voicingFormula([0, 4, 7, 21]), '1-3-5-13');
      expect(voicingFormula([0, 3, 10, 20]), '1-b3-b7-b13');
    });
    test('the same tones below the octave stay simple', () {
      expect(voicingFormula([0, 2, 4, 7]), '1-2-3-5');
      expect(voicingFormula([0, 4, 5, 7]), '1-3-4-5');
      expect(voicingFormula([0, 4, 7, 9]), '1-3-5-6');
    });
    test('structural tones and altered degrees are never relabelled', () {
      expect(voicingFormula([0, 12]), '1-1'); // octave-doubled root
      expect(voicingFormula([0, 7, 16, 19]), '1-5-3-5'); // 5th an 8va up
      expect(voicingFormula([0, 10, 15]), '1-b7-b3'); // b3 stays b3, not #9
      expect(voicingFormula([0, 4, 23]), '1-3-7'); // 7th an 8va up
    });
    test('empty offsets yield an empty formula', () {
      expect(voicingFormula([]), '');
    });
  });

  group('encode / decode', () {
    test('round-trips a negative-offset shape exactly', () {
      final s = VoicingSpec(
        id: 'v123',
        name: 'My drop 2',
        rootPc: 0,
        offsets: drop2,
        createdAt: DateTime.fromMicrosecondsSinceEpoch(1786417473791000),
      );
      final back = VoicingSpec.decode(s.encode())!;
      expect(back.id, s.id);
      expect(back.name, s.name);
      expect(back.rootPc, s.rootPc);
      expect(back.offsets, drop2); // negatives survive
      expect(back.createdAt, s.createdAt);
      expect(back.sig, s.sig);
      expect(back.formula, s.formula);
    });
    test('names with delimiters, quotes and unicode survive', () {
      for (final name in ['a|b|c', 'He said "hi"', 'Ré ♭9', r'back\slash']) {
        expect(VoicingSpec.decode(spec(drop2, name: name).encode())!.name, name);
      }
    });
    test('malformed lines decode to null instead of throwing', () {
      expect(VoicingSpec.decode('not json'), isNull);
      expect(VoicingSpec.decode(''), isNull);
      expect(VoicingSpec.decode('{}'), isNull);
      expect(VoicingSpec.decode('[1,2,3]'), isNull);
      expect(VoicingSpec.decode('{"id":"x","name":"y"}'), isNull);
      expect(
        VoicingSpec.decode(spec([]).encode()), // no offsets
        isNull,
      );
    });
    test('fromNotes captures a played shape', () {
      final s = VoicingSpec.fromNotes(
        name: 'Drop 2',
        rootPc: 0,
        notes: [67, 59, 72, 64], // unsorted
      );
      expect(s.offsets, drop2);
      expect(s.formula, '7-3-5-1');
      expect(s.id, isNotEmpty);
    });
  });

  group('matches — octave-agnostic, order-strict', () {
    final s = spec(drop2); // sig [0,5,8,13], bass = the 7th

    test('right shape, wrong register passes', () {
      expect(s.matches([59, 64, 67, 72], 0), isTrue);
      expect(s.matches([47, 52, 55, 60], 0), isTrue); // an octave down
      expect(s.matches([71, 76, 79, 84], 0), isTrue); // an octave up
    });
    test('input order does not matter', () {
      expect(s.matches([72, 59, 67, 64], 0), isTrue);
    });
    test('transposes with the key', () {
      expect(s.matches([64, 69, 72, 77], 5), isTrue); // the drop 2 in F
      expect(s.matches([59, 64, 67, 72], 5), isFalse); // still in C
    });
    test('right pitch classes, wrong spacing fails', () {
      expect(s.matches([60, 64, 67, 71], 0), isFalse); // close Cmaj7
      expect(s.matches([64, 67, 71, 72], 0), isFalse); // 1st inversion
    });
    test('right spacing, wrong bass fails', () {
      expect(s.matches([60, 65, 68, 73], 0), isFalse); // drop 2 shape in Db
    });
    test('wrong note count fails', () {
      expect(s.matches([59, 64, 67], 0), isFalse);
      expect(s.matches([59, 64, 67, 72, 76], 0), isFalse);
      expect(s.matches([], 0), isFalse);
    });
  });

  group('VoicingCycle — chromatic sequencing', () {
    final cycle = VoicingCycle(spec(openTriad));

    test('runs 25 steps', () => expect(cycle.length, 25));
    test('ascends 12 semitones then descends, apex played once', () {
      expect([for (final s in cycle.steps) s.keyPc], [
        0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, //
        0, // apex, an octave above the start
        11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0,
      ]);
    });
    test('the apex is an octave above the first step, not a repeat', () {
      expect(cycle.steps[12].notes.first, cycle.steps[0].notes.first + 12);
      expect(cycle.steps[24].notes, cycle.steps[0].notes);
    });
    test('register climbs a semitone per step, then walks back down', () {
      final lows = [for (final s in cycle.steps) s.notes.first];
      expect(lows.sublist(0, 13), [for (var i = 0; i <= 12; i++) 48 + i]);
      expect(lows.sublist(12), [for (var i = 12; i >= 0; i--) 48 + i]);
    });
    test('starts from any key', () {
      final a = VoicingCycle(spec(openTriad), startPc: 9);
      expect([for (final s in a.steps) s.keyPc], [
        for (var i = 0; i <= 12; i++) (9 + i) % 12,
        for (var i = 11; i >= 0; i--) (9 + i) % 12,
      ]);
      expect(a.steps.first.notes.first, 57); // A3
    });
    test('a negative bass offset is placed so the shape stays on the board',
        () {
      final c = VoicingCycle(spec(drop2)); // bass sits a semitone under C
      expect(c.steps.first.notes, [59, 64, 67, 72]); // root C4, not C3
      expect(c.steps.first.notes.first, greaterThanOrEqualTo(48));
      expect(c.steps[12].notes.last, 84); // apex tops out exactly at C6
    });
    test('every step is a correct realisation of the spec', () {
      for (final s in cycle.steps) {
        expect(s.bassPc, cycle.spec.bassPcIn(s.keyPc));
        expect(cycle.spec.matches(s.notes, s.keyPc), isTrue);
      }
    });
    test('labels are key names', () {
      expect(cycle.steps[6].label, 'F#');
      expect(cycle.steps.first.label, 'C');
    });
  });

  group('VoicingCycle — fifths sequencing', () {
    final cycle = VoicingCycle(spec([0, 4, 7]), increment: KeyIncrement.fifths);

    test('runs 12 keys, no descent', () => expect(cycle.length, 12));
    test('walks the circle of fifths, each key once', () {
      final pcs = [for (final s in cycle.steps) s.keyPc];
      expect(pcs, [0, 7, 2, 9, 4, 11, 6, 1, 8, 3, 10, 5]);
      expect(pcs.toSet().length, 12);
    });
    test('the anchor drops an octave rather than running off the top', () {
      expect([for (final s in cycle.steps) s.notes.first],
          [48, 55, 62, 69, 76, 71, 66, 73, 68, 75, 70, 77]);
    });
    test('every step fits the keyboard and still matches', () {
      for (final s in cycle.steps) {
        expect(s.notes.first, greaterThanOrEqualTo(48));
        expect(s.notes.last, lessThanOrEqualTo(84));
        expect(cycle.spec.matches(s.notes, s.keyPc), isTrue);
      }
    });
    test('starts from any key', () {
      final f = VoicingCycle(spec([0, 4, 7]),
          startPc: 5, increment: KeyIncrement.fifths);
      expect([for (final s in f.steps) s.keyPc],
          [5, 0, 7, 2, 9, 4, 11, 6, 1, 8, 3, 10]);
    });
  });

  group('VoicingCycle — octave fold boundary', () {
    test('no fold while the top note still fits', () {
      final c = VoicingCycle(spec([0, 4, 7]), keyboardHigh: 67);
      expect(c.steps[12].notes, [60, 64, 67]); // apex, exactly at the ceiling
    });
    test('one semitone tighter and the apex folds down an octave', () {
      final c = VoicingCycle(spec([0, 4, 7]), keyboardHigh: 66);
      expect(c.steps[12].notes, [48, 52, 55]);
      expect(c.steps[12].keyPc, 0); // folding never changes the key
      expect(c.spec.matches(c.steps[12].notes, c.steps[12].keyPc), isTrue);
    });
    test('a shape wider than the keyboard is left alone, not folded off it',
        () {
      final c = VoicingCycle(spec([0, 40]));
      expect(c.length, 25);
      expect(c.steps.first.notes, [48, 88]);
      expect(c.steps.first.keyPc, 0);
    });
  });

  group('playableNotes — putting a saved shape back under the fingers', () {
    test('the reference drop 2 comes back as the notes it was captured from',
        () {
      expect(spec(drop2).playableNotes(), [59, 64, 67, 72]);
    });
    test('lands in the same register the drill opens in', () {
      final s = spec(drop2);
      expect(s.playableNotes(), VoicingCycle(s).steps.first.notes);
    });
    test('sits on the keyboard for every root', () {
      for (var pc = 0; pc < 12; pc++) {
        final notes = spec(drop2, rootPc: pc).playableNotes();
        expect(notes.first, greaterThanOrEqualTo(kVoicingKeyboardLow));
        expect(notes.last, lessThanOrEqualTo(kVoicingKeyboardHigh));
      }
    });
    test('round-trips: capture → save → edit reads back the same offsets', () {
      // Everything the capture screen can produce, including the shapes that
      // put a voice below the root. (An offsets.first of exactly -6 is the one
      // case that would shift, and the root rule's downward tie-break means
      // capture can never produce it.)
      for (final offsets in [drop2, openTriad, rootlessA, [-5, 0, 4, 9]]) {
        for (var pc = 0; pc < 12; pc++) {
          final saved = spec(offsets, rootPc: pc);
          expect(offsetsFrom(saved.playableNotes(), pc), offsets,
              reason: 'offsets $offsets in ${saved.rootName}');
        }
      }
    });
  });

  group('sameShapeAs — the duplicate-save warning', () {
    test('identical shape and root', () {
      expect(spec(drop2).sameShapeAs(spec(drop2)), isTrue);
    });
    test('same notes captured an octave apart still count as one voicing', () {
      expect(spec(drop2).sameShapeAs(spec([11, 16, 19, 24])), isTrue);
    });
    test('a close voicing never matches its own drop 2', () {
      // Same four pitch classes, different spacing — the whole point of the
      // mode is that these are two different things to practise.
      expect(spec([0, 4, 7, 11]).sameShapeAs(spec(drop2)), isFalse);
    });
    test('same spacing but a different chord tone in the bass', () {
      // Both are [0,7,16] wide; the second puts the 5th on the bottom.
      expect(spec(openTriad).sameShapeAs(spec([7, 14, 23])), isFalse);
    });
    test('same spacing read from a different root is a different voicing', () {
      expect(spec(drop2).sameShapeAs(spec(drop2, rootPc: 5)), isFalse);
    });
    test('a different note count never matches', () {
      expect(spec(openTriad).sameShapeAs(spec([0, 7])), isFalse);
    });
  });
}
