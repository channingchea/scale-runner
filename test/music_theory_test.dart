import 'package:flutter_test/flutter_test.dart';
import 'package:scale_runner/theory/music_theory.dart';
import 'package:scale_runner/quiz/validators.dart';

void main() {
  group('pitch helpers', () {
    test('pitch class of MIDI notes', () {
      expect(pitchClassOf(60), 0); // C
      expect(pitchClassOf(61), 1); // C#
      expect(pitchClassOf(72), 0); // C an octave up
      expect(pitchClassOf(71), 11); // B
    });

    test('octave (scientific pitch notation)', () {
      expect(octaveOf(60), 4); // middle C = C4
      expect(octaveOf(48), 3);
      expect(octaveOf(72), 5);
    });

    test('note names', () {
      expect(noteName(60), 'C4');
      expect(noteName(61), 'C#4');
      expect(noteName(69), 'A4'); // A440
      expect(noteName(21), 'A0'); // lowest piano key
    });
  });

  group('ScaleFormula', () {
    final major = commonScales.firstWhere((s) => s.name.startsWith('Major'));

    test('C major notes from middle C, with octave on top', () {
      expect(major.notesFrom(60), [60, 62, 64, 65, 67, 69, 71, 72]);
    });

    test('C major notes without octave', () {
      expect(major.notesFrom(60, includeOctave: false),
          [60, 62, 64, 65, 67, 69, 71]);
    });

    test('pitch classes of A major', () {
      expect(major.pitchClasses(9), {9, 11, 1, 2, 4, 6, 8});
    });

    test('all common scales are well-formed', () {
      for (final s in commonScales) {
        expect(s.intervals.first, 0, reason: '${s.name} should start at root');
        expect(s.intervals, equals([...s.intervals]..sort()),
            reason: '${s.name} intervals should be ascending');
        expect(s.intervals.last, lessThan(12),
            reason: '${s.name} stays within one octave');
      }
    });
  });

  group('ChordFormula inversions', () {
    final cMajor = commonChords.firstWhere((c) => c.name == 'Major');

    test('root position C major triad', () {
      expect(cMajor.notesFrom(60), [60, 64, 67]); // C E G
    });

    test('first inversion moves root up an octave', () {
      expect(cMajor.inversion(60, 1), [64, 67, 72]); // E G C
    });

    test('second inversion', () {
      expect(cMajor.inversion(60, 2), [67, 72, 76]); // G C E
    });

    test('inversion count equals number of chord tones', () {
      expect(cMajor.inversionCount, 3);
      final dom7 = commonChords.firstWhere((c) => c.name == 'Dominant 7th');
      expect(dom7.inversionCount, 4);
    });

    test('inversions preserve pitch-class content', () {
      final dom7 = commonChords.firstWhere((c) => c.name == 'Dominant 7th');
      final rootPcs = dom7.notesFrom(60).map(pitchClassOf).toSet();
      for (var i = 0; i < dom7.inversionCount; i++) {
        expect(dom7.inversion(60, i).map(pitchClassOf).toSet(), rootPcs);
      }
    });
  });

  group('ScaleValidator (sequential)', () {
    ScaleValidator cMajor() => ScaleValidator.fromFormula(
        commonScales.firstWhere((s) => s.name.startsWith('Major')), 60);

    test('correct ascending run completes', () {
      final v = cMajor();
      final run = [60, 62, 64, 65, 67, 69, 71, 72];
      for (var i = 0; i < run.length - 1; i++) {
        expect(v.onNoteOn(run[i]), ValidationStatus.inProgress);
      }
      expect(v.onNoteOn(run.last), ValidationStatus.complete);
      expect(v.isComplete, isTrue);
    });

    test('octave-agnostic: same pitch classes in any octave', () {
      final v = cMajor();
      // Play the C-major pitch classes but shifted around octaves.
      final run = [48, 50, 52, 53, 55, 57, 59, 72];
      for (var i = 0; i < run.length - 1; i++) {
        expect(v.onNoteOn(run[i]), ValidationStatus.inProgress);
      }
      expect(v.onNoteOn(run.last), ValidationStatus.complete);
    });

    test('wrong note fails the attempt', () {
      final v = cMajor();
      expect(v.onNoteOn(60), ValidationStatus.inProgress); // C ok
      expect(v.onNoteOn(63), ValidationStatus.wrong); // D# not in C major
      expect(v.progress, 1); // did not advance past the wrong note
    });

    test('reset allows a clean replay', () {
      final v = cMajor();
      v.onNoteOn(60);
      v.onNoteOn(63); // wrong
      v.reset();
      expect(v.progress, 0);
      expect(v.onNoteOn(60), ValidationStatus.inProgress);
    });
  });

  group('ChordValidator (simultaneous)', () {
    ChordValidator cMajor() => ChordValidator.fromFormula(
        commonChords.firstWhere((c) => c.name == 'Major'), 60);

    test('exact set completes', () {
      expect(cMajor().evaluate({60, 64, 67}), ValidationStatus.complete);
    });

    test('octave-agnostic voicing still completes', () {
      // C E G spread across octaves.
      expect(cMajor().evaluate({48, 64, 79}), ValidationStatus.complete);
    });

    test('partial chord is in progress', () {
      expect(cMajor().evaluate({60, 64}), ValidationStatus.inProgress);
    });

    test('empty held set is in progress, not complete', () {
      expect(cMajor().evaluate({}), ValidationStatus.inProgress);
    });

    test('an extra/wrong note fails', () {
      expect(cMajor().evaluate({60, 64, 67, 66}), ValidationStatus.wrong);
    });

    test('a single wrong note fails', () {
      expect(cMajor().evaluate({61}), ValidationStatus.wrong);
    });
  });
}
