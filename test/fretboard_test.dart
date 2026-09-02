import 'package:flutter_test/flutter_test.dart';

import 'package:scale_runner/audio/note_player.dart';
import 'package:scale_runner/theory/fretboard.dart';
import 'package:scale_runner/theory/inversion_running.dart';
import 'package:scale_runner/theory/music_theory.dart';

void main() {
  const t = Tuning.standard;

  group('Instrument', () {
    test('decodes a stored name and defaults to piano', () {
      expect(Instrument.byName('guitar'), Instrument.guitar);
      expect(Instrument.byName('piano'), Instrument.piano);
      expect(Instrument.byName(null), Instrument.piano);
      expect(Instrument.byName('theremin'), Instrument.piano);
    });
  });

  group('Tuning', () {
    test('standard tuning runs low E to high E', () {
      expect(t.openStrings, [40, 45, 50, 55, 59, 64]);
      expect(t.stringCount, 6);
      expect(t.lowest, 40);
      expect(t.highest(), 86);
      expect(t.midiAt(0, 0), 40);
      expect(t.midiAt(5, 12), 76);
    });
  });

  group('positionsFor', () {
    test('a note over the piano keyboard has 2 to 5 places on the neck', () {
      for (var midi = 48; midi <= 72; midi++) {
        final n = positionsFor(midi).length;
        expect(n, greaterThanOrEqualTo(2), reason: 'MIDI $midi');
        expect(n, lessThanOrEqualTo(5), reason: 'MIDI $midi');
      }
    });

    test('every cell reports itself, so a tap is never ambiguous', () {
      for (var s = 0; s < t.stringCount; s++) {
        for (var f = 0; f <= kMaxFret; f++) {
          expect(positionsFor(t.midiAt(s, f)), contains(FretPosition(s, f)));
        }
      }
    });

    test('notes off the instrument have nowhere to go', () {
      expect(positionsFor(39), isEmpty);
      expect(positionsFor(87), isEmpty);
      expect(positionsFor(40), [const FretPosition(0, 0)]);
      expect(positionsFor(86), [const FretPosition(5, 22)]);
    });
  });

  group('FretBox', () {
    test('holds its own frets and measures the distance to the rest', () {
      const box = FretBox(5);
      expect(box.end, 9);
      expect(box.contains(5), isTrue);
      expect(box.contains(9), isTrue);
      expect(box.contains(4), isFalse);
      expect(box.distanceTo(7), 0);
      expect(box.distanceTo(2), 3);
      expect(box.distanceTo(12), 3);
    });

    test('slides back onto the neck rather than hanging off it', () {
      expect(const FretBox(-3).clamped(), const FretBox(0));
      expect(const FretBox(21).clamped(), const FretBox(18));
      expect(const FretBox(5).clamped(), const FretBox(5));
    });
  });

  group('primaryFor', () {
    test('an in-box position beats one outside', () {
      // MIDI 55 is open D (string 3) and fret 5 of A (string 2).
      final p = primaryFor(55, const FretBox(3))!;
      expect(p, const FretPosition(2, 5));
    });

    test('among in-box twins the higher string wins', () {
      // MIDI 59 sits at string 3 fret 4 and string 4 fret 0; a box at 0-4
      // holds both.
      expect(primaryFor(59, const FretBox(0)), const FretPosition(4, 0));
    });

    test('with nothing in the box the nearest position still lights up', () {
      final p = primaryFor(48, const FretBox(15))!;
      expect(p.midi(), 48);
      expect(p.fret, lessThan(15));
    });

    test('is null only for a note the instrument does not have', () {
      expect(primaryFor(39, const FretBox(0)), isNull);
      expect(primaryFor(100, const FretBox(0)), isNull);
    });
  });

  group('boxFor', () {
    test('one five-fret box holds every quiz round, scale or chord', () {
      // The quiz hints exact MIDI notes with the root in 48-59.
      for (var root = 48; root <= 59; root++) {
        for (final scale in commonScales) {
          final targets = scale.notesFrom(root);
          final box = boxFor(targets);
          expect(box.width, kBoxWidth,
              reason: '${scale.name} from $root needed ${box.width} frets');
          for (final n in targets) {
            expect(positionsFor(n).any((p) => box.contains(p.fret)), isTrue,
                reason: '${scale.name} from $root: MIDI $n is outside $box');
          }
        }
        for (final chord in commonChords) {
          final targets = chord.notesFrom(root);
          final box = boxFor(targets);
          expect(box.width, kBoxWidth,
              reason: '${chord.name} from $root needed ${box.width} frets');
          for (final n in targets) {
            expect(positionsFor(n).any((p) => box.contains(p.fret)), isTrue,
                reason: '${chord.name} from $root: MIDI $n is outside $box');
          }
        }
      }
    });

    test('ignores notes the instrument cannot play instead of giving up', () {
      final box = boxFor([39, 60, 64, 67]);
      for (final n in [60, 64, 67]) {
        expect(positionsFor(n).any((p) => box.contains(p.fret)), isTrue);
      }
    });

    test('an empty target set still yields a usable box', () {
      expect(boxFor(const []), const FretBox(0));
    });
  });

  group('boxAtRoot', () {
    test('every key root lands on the A string at fret 3 or higher', () {
      for (var pc = 0; pc < 12; pc++) {
        final box = boxAtRoot(pc);
        final rootFret = box.start + 1;
        expect(rootFret, greaterThanOrEqualTo(3),
            reason: 'pc $pc anchored at fret $rootFret');
        expect(rootFret, lessThanOrEqualTo(kComfortFret - 1));
        expect(Tuning.standard.midiAt(kRootAnchorString, rootFret) % 12, pc);
        expect(box.contains(rootFret), isTrue);
        expect(box.width, kBoxWidth);
      }
    });

    test('the familiar positions come out where a player expects them', () {
      expect(boxAtRoot(0), const FretBox(2)); // C, frets 2-6
      expect(boxAtRoot(7), const FretBox(9)); // G, frets 9-13
      expect(boxAtRoot(4), const FretBox(6)); // E, frets 6-10
    });

    test('the box depends on the key alone, never on which notes are lit', () {
      // The whole point: two different moments in the same key agree.
      expect(boxAtRoot(0), boxAtRoot(0));
      expect(boxAtRoot(0) == boxAtRoot(2), isFalse);
    });
  });

  group('boxForShape', () {
    test('a close maj7 is drawn as a hand, not as two notes on one string', () {
      const notes = [60, 64, 67, 71];
      // boxFor only promises reachability, and here that stacks two notes on
      // the high E. The fitted box is the shape you can actually hold.
      final shape = fit(notes)!;
      expect(boxForShape(notes), shape.box());
      final strings = shape.positions.map((p) => p.string).toSet();
      expect(strings.length, notes.length);
    });

    test('every Inversion Running step is drawn at its playable shape', () {
      for (final chord in commonChords) {
        for (var rootPc = 0; rootPc < 12; rootPc++) {
          final cycle =
              InversionCycle(chord, rootPc, instrument: Instrument.guitar);
          for (final step in cycle.steps) {
            expect(fits(step.notes, adjacentOnly: true), isTrue,
                reason: '${chord.name} $rootPc: ${step.notes} does not fit');
            final box = boxForShape(step.notes, adjacentOnly: true);
            final shape = fit(step.notes, adjacentOnly: true)!;
            for (final pos in shape.positions) {
              expect(box.contains(pos.fret), isTrue);
            }
          }
        }
      }
    });

    test('an unholdable shape degrades to boxFor rather than blanking', () {
      const spread = [48, 60, 72, 84]; // three octaves, no hand covers it
      expect(fits(spread), isFalse);
      expect(boxForShape(spread), boxFor(spread));
    });
  });

  group('hint density in a box', () {
    test('a scale paints at most 20 dots, against 15-ish on the piano', () {
      // This is the number that makes the box mandatory: the same pitch-class
      // hint covers 84 cells on a whole 22-fret neck.
      for (final scale in commonScales) {
        if (scale.intervals.length > 7) continue; // Chromatic fills any box
        for (var rootPc = 0; rootPc < 12; rootPc++) {
          final pcs = scale.pitchClasses(rootPc);
          for (var start = 0; start + kBoxWidth - 1 <= kMaxFret; start++) {
            final box = FretBox(start);
            var dots = 0;
            for (var s = 0; s < t.stringCount; s++) {
              for (var f = box.start; f <= box.end; f++) {
                if (pcs.contains(t.midiAt(s, f) % 12)) dots++;
              }
            }
            expect(dots, lessThanOrEqualTo(20),
                reason: '${scale.name} in ${pitchClassNames[rootPc]}, $box');
          }
        }
      }
    });
  });

  group('fit', () {
    test('places a C major triad low on the neck, ascending', () {
      final shape = fit([60, 64, 67], adjacentOnly: true)!;
      expect(shape.positions.length, 3);
      for (var i = 0; i < 3; i++) {
        expect(shape.positions[i].midi(), [60, 64, 67][i]);
      }
      // Strings ascend with pitch, and adjacent means consecutive.
      for (var i = 1; i < 3; i++) {
        expect(shape.positions[i].string, shape.positions[i - 1].string + 1);
      }
      expect(shape.span, lessThanOrEqualTo(kBoxWidth - 1));
      expect(shape.highestFret, 5); // the lowest placement that works
    });

    test('adjacentOnly off lets an open shape skip a string', () {
      // 1-5-10: a tenth above the root cannot sit on the next string over.
      final shape = fit([48, 55, 64])!;
      expect(shape.positions.map((p) => p.midi()), [48, 55, 64]);
      expect(shape.span, lessThanOrEqualTo(kBoxWidth - 1));
    });

    test('refuses what a hand cannot hold', () {
      expect(fit([48, 49, 50, 51, 52, 53, 54]), isNull); // seven notes
      expect(fit([39, 60, 64]), isNull); // off the neck
      expect(fit([48, 60, 72, 84], adjacentOnly: true), isNull); // too wide
      expect(fit(const []), isNull);
    });

    test('a fitted shape always sits inside its own box', () {
      final shape = fit([60, 64, 67], adjacentOnly: true)!;
      final box = shape.box();
      for (final p in shape.positions) {
        expect(box.contains(p.fret), isTrue);
      }
      expect(box.width, greaterThanOrEqualTo(kBoxWidth));
    });
  });

  group('drop2 and guitarVoicing', () {
    test('drop2 drops the second voice from the top', () {
      expect(drop2([60, 64, 67, 71]), [55, 60, 64, 71]);
      expect(drop2([60, 64, 67]), [60, 64, 67]); // triads untouched
    });

    test('a close 7th becomes the drop 2 with the same note in the bass', () {
      // C E G B close -> C G B E, the standard root-position drop 2.
      expect(guitarVoicing([60, 64, 67, 71], comfortFret: kMaxFret),
          [60, 67, 71, 76]);
    });

    test('triads stay in close position', () {
      expect(guitarVoicing([60, 64, 67]), [60, 64, 67]);
    });

    test('pitch classes and the bass pitch class always survive', () {
      for (final chord in commonChords) {
        for (var rootPc = 0; rootPc < 12; rootPc++) {
          for (var inv = 0; inv <= chord.inversionCount; inv++) {
            final close = chord.inversion(60 + rootPc, inv);
            final guitar = guitarVoicing(close);
            expect({for (final n in guitar) n % 12},
                {for (final n in close) n % 12},
                reason: '${chord.name} $rootPc inv $inv');
            expect(guitar.first % 12, close.first % 12,
                reason: '${chord.name} $rootPc inv $inv bass');
          }
        }
      }
    });
  });

  group('InversionCycle on guitar', () {
    test('the piano path is untouched by the instrument flag', () {
      for (final chord in commonChords) {
        for (var rootPc = 0; rootPc < 12; rootPc++) {
          final withFlag =
              InversionCycle(chord, rootPc, instrument: Instrument.piano);
          final without = InversionCycle(chord, rootPc);
          for (var i = 0; i < without.steps.length; i++) {
            expect(withFlag.steps[i].notes, without.steps[i].notes);
            expect(without.steps[i].notes,
                chord.inversion(without.lowMidi, without.steps[i].inversion));
          }
        }
      }
    });

    test('every chord in every key is playable, and still climbs', () {
      for (final chord in commonChords) {
        for (var rootPc = 0; rootPc < 12; rootPc++) {
          final piano = InversionCycle(chord, rootPc);
          final guitar =
              InversionCycle(chord, rootPc, instrument: Instrument.guitar);
          final where = '${chord.name} in ${pitchClassNames[rootPc]}';

          expect(guitar.steps.length, piano.steps.length, reason: where);
          for (var i = 0; i < guitar.steps.length; i++) {
            final step = guitar.steps[i];

            // Judging reads pitch classes and the bass, and neither moves.
            expect(step.pitchClasses, piano.steps[i].pitchClasses,
                reason: '$where step $i');
            expect(step.bassPc, piano.steps[i].bassPc,
                reason: '$where step $i bass');

            // Every voicing sits under one hand on consecutive strings.
            final shape = fit(step.notes, adjacentOnly: true);
            expect(shape, isNotNull, reason: '$where step $i does not fit');
            expect(shape!.span, lessThanOrEqualTo(kBoxWidth - 1),
                reason: '$where step $i spans ${shape.span}');
            // 15 is the comfort target; one fret past it beats not fitting.
            expect(shape.highestFret, lessThanOrEqualTo(kComfortFret + 1),
                reason: '$where step $i reaches fret ${shape.highestFret}');

            // And it makes a sound.
            for (final n in step.notes) {
              expect(n, greaterThanOrEqualTo(NotePlayer.lowMidi),
                  reason: '$where step $i');
              expect(n, lessThanOrEqualTo(NotePlayer.highMidi),
                  reason: '$where step $i');
            }
          }

          // The ascent to the apex rises, top and bottom, every step.
          final apex = chord.inversionCount;
          for (var i = 1; i <= apex; i++) {
            expect(guitar.steps[i].notes.first,
                greaterThan(guitar.steps[i - 1].notes.first),
                reason: '$where step $i bass did not rise');
            expect(guitar.steps[i].notes.last,
                greaterThan(guitar.steps[i - 1].notes.last),
                reason: '$where step $i top did not rise');
          }
          // The whole point of the apex: it is not where we started.
          expect(guitar.steps[apex].notes, isNot(guitar.steps[0].notes),
              reason: '$where apex collapsed onto root position');
        }
      }
    });
  });
}
