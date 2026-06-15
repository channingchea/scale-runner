import 'package:audioplayers/audioplayers.dart';

/// Plays a short piano-like sample for each key in the on-screen keyboard
/// range (C3–C5). Uses a small pool of low-latency players so fast runs and
/// held chords can sound polyphonically instead of cutting each other off.
class NotePlayer {
  /// Sample range — matches the quiz keyboard (C3 to the C two octaves up).
  static const int lowMidi = 48;
  static const int highMidi = 72;

  static const int _poolSize = 10;

  final List<AudioPlayer> _pool = [
    for (var i = 0; i < _poolSize; i++)
      AudioPlayer()
        ..setPlayerMode(PlayerMode.lowLatency)
        ..setReleaseMode(ReleaseMode.stop),
  ];
  int _next = 0;

  /// Sound [midiNote]. Notes outside the sampled range are ignored (MIDI
  /// keyboards can send any pitch; we only ship samples for the app's range).
  void play(int midiNote) {
    if (midiNote < lowMidi || midiNote > highMidi) return;
    final player = _pool[_next];
    _next = (_next + 1) % _poolSize;
    player
      ..stop()
      ..play(AssetSource('audio/note_$midiNote.wav'));
  }

  void dispose() {
    for (final p in _pool) {
      p.dispose();
    }
  }
}
