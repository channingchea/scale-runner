import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:scale_runner/audio/note_player.dart';
import 'package:scale_runner/theory/inversion_running.dart';
import 'package:scale_runner/theory/music_theory.dart';
import 'package:scale_runner/theory/voicings.dart';

/// Guards the promise that every note a drill can highlight also makes a
/// sound. The old 48-77 sample set silently dropped anything above F5, so
/// Inversion Running's apex and the top of a transposed voicing were mute.
/// If a cycle ever climbs higher than the samples reach, this fails instead
/// of going quiet.
void main() {
  VoicingSpec spec(String name, List<int> offsets) => VoicingSpec(
        id: name,
        name: name,
        rootPc: 0,
        offsets: offsets,
        createdAt: DateTime.utc(2026),
      );

  bool inRange(int midi) =>
      midi >= NotePlayer.lowMidi && midi <= NotePlayer.highMidi;

  group('NotePlayer range covers every drill', () {
    test('every Inversion Running note in every chord and key sounds', () {
      var highest = 0;
      var lowest = 1 << 30;
      for (final chord in commonChords) {
        for (var rootPc = 0; rootPc < 12; rootPc++) {
          for (final step in InversionCycle(chord, rootPc).steps) {
            for (final note in step.notes) {
              expect(inRange(note), isTrue,
                  reason: '${chord.name} in ${pitchClassNames[rootPc]}, '
                      '${step.label}: MIDI $note is outside '
                      '${NotePlayer.lowMidi}-${NotePlayer.highMidi}');
              if (note > highest) highest = note;
              if (note < lowest) lowest = note;
            }
          }
        }
      }
      // Pinned, so a change to the cycle's shape shows up here.
      expect(lowest, 60);
      expect(highest, 94); // B Major 7th, Root (8va)
    });

    test('every Voicings drill note sounds, in both key increments', () {
      // Shapes chosen to stress the placement rule: a close triad, a drop 2
      // with a note below the root, and the widest shape the 48-84 capture
      // keyboard can produce, which is the case _fitRoot cannot fold.
      final shapes = [
        spec('close triad', [0, 4, 7]),
        spec('drop 2', [-1, 4, 7, 12]),
        spec('full width', [0, 36]),
      ];
      var highest = 0;
      var lowest = 1 << 30;
      for (final s in shapes) {
        for (final increment in KeyIncrement.values) {
          for (var startPc = 0; startPc < 12; startPc++) {
            final cycle =
                VoicingCycle(s, startPc: startPc, increment: increment);
            for (final step in cycle.steps) {
              for (final note in step.notes) {
                expect(inRange(note), isTrue,
                    reason: '${s.name} from ${pitchClassNames[startPc]} '
                        '(${increment.name}), key ${step.label}: MIDI $note '
                        'is outside ${NotePlayer.lowMidi}-'
                        '${NotePlayer.highMidi}');
                if (note > highest) highest = note;
                if (note < lowest) lowest = note;
              }
            }
          }
        }
      }
      expect(lowest, kVoicingKeyboardLow);
      expect(highest, 95); // a 3-octave shape in B has nowhere left to fold
    });

    test('a sample file exists for every note in the range', () {
      final missing = [
        for (var m = NotePlayer.lowMidi; m <= NotePlayer.highMidi; m++)
          if (!File('assets/audio/note_$m.wav').existsSync()) m,
      ];
      expect(missing, isEmpty,
          reason: 'run: python3 tool/gen_note_samples.py --missing');
    });

    test('every sample is 22050 Hz mono 16-bit and 1.1 s long', () {
      // Read straight out of the RIFF header, so a file regenerated with the
      // wrong settings cannot slip in next to the originals.
      for (var m = NotePlayer.lowMidi; m <= NotePlayer.highMidi; m++) {
        final bytes = File('assets/audio/note_$m.wav').readAsBytesSync();
        final head = ByteData.sublistView(Uint8List.fromList(bytes));
        expect(head.getUint16(22, Endian.little), 1,
            reason: 'note_$m channels');
        expect(head.getUint32(24, Endian.little), 22050,
            reason: 'note_$m sample rate');
        expect(head.getUint16(34, Endian.little), 16,
            reason: 'note_$m bit depth');
        expect(bytes.length, 44 + 24255 * 2, reason: 'note_$m length');
      }
    });
  });
}
