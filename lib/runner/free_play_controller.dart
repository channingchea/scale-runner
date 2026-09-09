import 'dart:async';

import 'package:flutter/foundation.dart';

import '../midi/midi_service.dart';
import '../quiz/quiz_controller.dart' show KeyFeedback;
import '../theory/chord_namer.dart';

/// Free Play: no prompt, no judgment — just the set of notes sounding and a
/// live name for it. Input arrives from on-screen taps ([pressKey] /
/// [releaseKey]) and from MIDI ([bindMidi], or [noteOn] / [noteOff]).
///
/// With [latchTaps] on (the Arpeggiated Notes setting), a tapped note stays
/// sounding after the finger lifts so a mouse or a single finger can build a
/// chord one note at a time. Tapping a latched key again releases it, and
/// [latchIdle] with no new tap clears the lot. MIDI notes never latch: a real
/// instrument has to hold its notes.
class FreePlayController extends ChangeNotifier {
  FreePlayController({this._latchTaps = false});

  /// How long a latched chord survives without a new tap.
  static const Duration latchIdle = Duration(seconds: 2);

  bool _latchTaps;
  bool get latchTaps => _latchTaps;
  set latchTaps(bool on) {
    if (on == _latchTaps) return;
    _latchTaps = on;
    if (!on) _clearLatch();
    notifyListeners();
  }

  /// Notes physically down right now: unlatched taps and MIDI keys.
  final Set<int> _held = {};

  /// Tapped notes kept sounding by the latch.
  final Set<int> _latched = {};
  Timer? _latchTimer;

  /// Everything sounding, held or latched.
  Set<int> get sounding => {..._held, ..._latched};

  /// The live name for [sounding], or null when nothing is.
  Readout? get readout => describeHeld(sounding);

  /// Fired on every new note (tap or MIDI) — e.g. to play its sound. Not
  /// fired when a tap releases a latched note.
  void Function(int midiNote)? onAnyPress;

  StreamSubscription<MidiNoteEvent>? _midiSub;

  void bindMidi(MidiService service) {
    _midiSub?.cancel();
    _midiSub = service.noteStream.listen((e) {
      if (e.isOn) {
        noteOn(e.note);
      } else {
        noteOff(e.note);
      }
    });
  }

  KeyFeedback feedbackFor(int midiNote) =>
      _held.contains(midiNote) || _latched.contains(midiNote)
          ? KeyFeedback.pressed
          : KeyFeedback.idle;

  bool isTargetHint(int midiNote) => false;

  // ---- Input ---------------------------------------------------------------

  /// An on-screen key went down.
  void pressKey(int midiNote) {
    if (!_latchTaps) {
      noteOn(midiNote);
      return;
    }
    if (_latched.remove(midiNote)) {
      // Second tap on a lit key puts it out.
      if (_latched.isEmpty) _latchTimer?.cancel();
    } else {
      _latched.add(midiNote);
      onAnyPress?.call(midiNote);
    }
    if (_latched.isNotEmpty) _restartLatchTimer();
    notifyListeners();
  }

  /// An on-screen key came up. A no-op for latched notes, which is the point.
  void releaseKey(int midiNote) => noteOff(midiNote);

  /// A MIDI key (or an unlatched tap) went down.
  void noteOn(int midiNote) {
    onAnyPress?.call(midiNote);
    _held.add(midiNote);
    notifyListeners();
  }

  /// A MIDI key (or an unlatched tap) came up.
  void noteOff(int midiNote) {
    if (_held.remove(midiNote)) notifyListeners();
  }

  void _restartLatchTimer() {
    _latchTimer?.cancel();
    _latchTimer = Timer(latchIdle, _clearLatch);
  }

  void _clearLatch() {
    _latchTimer?.cancel();
    _latchTimer = null;
    if (_latched.isEmpty) return;
    _latched.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _midiSub?.cancel();
    _latchTimer?.cancel();
    super.dispose();
  }
}
