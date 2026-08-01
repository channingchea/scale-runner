import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:scale_runner/midi/midi_service.dart';

void main() {
  group('parseMidiBytes', () {
    test('single note on', () {
      final events = parseMidiBytes(Uint8List.fromList([0x90, 60, 100]));
      expect(events, [const MidiNoteEvent(60, 100, true)]);
    });

    test('note on with velocity 0 is treated as note off', () {
      final events = parseMidiBytes(Uint8List.fromList([0x90, 60, 0]));
      expect(events, [const MidiNoteEvent(60, 0, false)]);
    });

    test('explicit note off', () {
      final events = parseMidiBytes(Uint8List.fromList([0x80, 60, 0]));
      expect(events, [const MidiNoteEvent(60, 0, false)]);
    });

    test('two note-ons coalesced into one packet (a chord over BLE)', () {
      final events = parseMidiBytes(
        Uint8List.fromList([0x90, 60, 100, 0x90, 64, 100, 0x90, 67, 100]),
      );
      expect(events, [
        const MidiNoteEvent(60, 100, true),
        const MidiNoteEvent(64, 100, true),
        const MidiNoteEvent(67, 100, true),
      ]);
    });

    test('running status: later messages omit the repeated status byte', () {
      // 0x90 60 100, then just "64 100" and "67 100" reusing status 0x90.
      final events = parseMidiBytes(
        Uint8List.fromList([0x90, 60, 100, 64, 100, 67, 100]),
      );
      expect(events, [
        const MidiNoteEvent(60, 100, true),
        const MidiNoteEvent(64, 100, true),
        const MidiNoteEvent(67, 100, true),
      ]);
    });

    test('interleaved note-off amongst note-ons', () {
      final events = parseMidiBytes(
        Uint8List.fromList([
          0x90, 60, 100, // note on 60
          0x90, 64, 100, // note on 64
          0x80, 60, 0, // note off 60
        ]),
      );
      expect(events, [
        const MidiNoteEvent(60, 100, true),
        const MidiNoteEvent(64, 100, true),
        const MidiNoteEvent(60, 0, false),
      ]);
    });

    test('lastStatus seeds running status for a buffer with no leading status byte', () {
      final events = parseMidiBytes(
        Uint8List.fromList([64, 100]),
        lastStatus: 0x90,
      );
      expect(events, [const MidiNoteEvent(64, 100, true)]);
    });

    test('System Real-Time bytes are skipped without disturbing running status', () {
      final events = parseMidiBytes(
        Uint8List.fromList([0x90, 60, 100, 0xF8, 64, 100]),
      );
      expect(events, [
        const MidiNoteEvent(60, 100, true),
        const MidiNoteEvent(64, 100, true),
      ]);
    });

    test('non-note channel messages are skipped by their known length', () {
      // Control Change (2 data bytes) then a note on.
      final events = parseMidiBytes(
        Uint8List.fromList([0xB0, 7, 127, 0x90, 60, 100]),
      );
      expect(events, [const MidiNoteEvent(60, 100, true)]);
    });

    test('unrecognized status stops parsing without throwing', () {
      final events = parseMidiBytes(
        Uint8List.fromList([0x90, 60, 100, 0xF0, 1, 2, 3]),
      );
      expect(events, [const MidiNoteEvent(60, 100, true)]);
    });

    test('empty buffer yields no events', () {
      expect(parseMidiBytes(Uint8List(0)), isEmpty);
    });
  });
}
