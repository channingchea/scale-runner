import 'dart:async';

import '../theory/fretboard.dart';

/// The Arpeggiated Notes latch: on-screen taps that stay sounding after the
/// finger lifts, so a chord can be built one note at a time.
///
/// Shared by the Chords quiz, Inversion Running, the Voicings drill and Free
/// Play. Each controller keeps one, adds tapped notes to it alongside its own
/// held set, and skips releases for notes the latch owns. The latch forgets
/// everything after [idle] with no new tap ([onExpire] lets the owner purge
/// its held set), and the owner clears it on a wrong note or a completed
/// chord. MIDI notes never go in here: a real instrument holds its own.
class NoteLatch {
  NoteLatch({this.idle = const Duration(seconds: 2), this.onExpire});

  /// How long a latched chord survives without a new tap.
  final Duration idle;

  /// Fired once when [idle] passes, with the notes just dropped, so the owner
  /// can take them off its keyboard too.
  void Function(Set<int> notes)? onExpire;

  final Set<int> _notes = {};
  Timer? _timer;

  /// The notes currently latched (a copy).
  Set<int> get notes => {..._notes};
  bool get isEmpty => _notes.isEmpty;
  bool get isNotEmpty => _notes.isNotEmpty;
  bool contains(int note) => _notes.contains(note);

  /// Latch [note] and restart the idle clock.
  void add(int note) {
    _notes.add(note);
    _restart();
  }

  /// A tap on a latched key puts it out; on any other key latches it.
  /// Returns true when the note is latched afterwards.
  bool toggle(int note) {
    if (_notes.remove(note)) {
      if (_notes.isEmpty) {
        _cancel();
      } else {
        _restart();
      }
      return false;
    }
    add(note);
    return true;
  }

  /// Drop [note] without touching the clock. No-op when it is not latched.
  bool remove(int note) => _notes.remove(note);

  /// Forget everything, silently (no [onExpire]).
  void clear() {
    _cancel();
    _notes.clear();
  }

  void dispose() => _cancel();

  void _restart() {
    _cancel();
    _timer = Timer(idle, () {
      _timer = null;
      if (_notes.isEmpty) return;
      final expired = {..._notes};
      _notes.clear();
      onExpire?.call(expired);
    });
  }

  void _cancel() {
    _timer?.cancel();
    _timer = null;
  }
}

/// Which notes a fretboard tap started and stopped, for the controller.
typedef LatchChange = ({Set<int> on, Set<int> off});

/// What [GuitarLatch.tapInto] needs from a drill controller.
abstract interface class LatchingInput {
  void pressKey(int midiNote, {bool latch});
  Set<int> get latchedNotes;
}

/// The latch's guitar half: the shape as cells, one per string.
///
/// A string sounds one note, so a latched tap on an occupied string replaces
/// that string's note, and a second tap on the same cell puts it out (the
/// rule Voicing capture has always used). The controller only understands
/// MIDI numbers, so [tap] reports the change as notes; the cells themselves
/// go back to the fretboard as `latched` so each one lights where it was
/// tapped rather than at the note's primary position.
class GuitarLatch {
  final Set<FretPosition> _cells = {};

  Set<FretPosition> get cells => _cells;
  bool get isEmpty => _cells.isEmpty;

  /// The notes the cells sound. Two cells can share a note (twin positions).
  Set<int> get notes => {for (final c in _cells) c.midi()};

  /// Apply a tap and report which notes stopped and started sounding. A note
  /// still supplied by another cell is neither.
  LatchChange tap(FretPosition cell) {
    final before = notes;
    if (!_cells.remove(cell)) {
      _cells.removeWhere((c) => c.string == cell.string);
      _cells.add(cell);
    }
    final after = notes;
    return (on: after.difference(before), off: before.difference(after));
  }

  /// Drop the cells whose notes the controller no longer holds — its latch
  /// expired, or a wrong note or a completed chord cleared it. Call before
  /// [tap] so a stale cell is not mistaken for a live one.
  void sync(Set<int> live) => _cells.removeWhere((c) => !live.contains(c.midi()));

  /// The whole guitar tap for a drill screen: forget stale cells, apply the
  /// tap, and hand the change to [controller] as latched presses (a latched
  /// press on a latched note puts it out).
  void tapInto(LatchingInput controller, FretPosition cell) {
    sync(controller.latchedNotes);
    final change = tap(cell);
    for (final n in change.off) {
      controller.pressKey(n, latch: true);
    }
    for (final n in change.on) {
      controller.pressKey(n, latch: true);
    }
  }

  void clear() => _cells.clear();
}
