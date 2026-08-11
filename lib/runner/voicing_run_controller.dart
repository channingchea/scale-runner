import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';

import '../midi/midi_service.dart';
import '../quiz/quiz_controller.dart' show KeyFeedback;
import '../theory/music_theory.dart';
import '../theory/voicings.dart';

/// The "brain" of the Voicings drill.
///
/// One shape, every key, self-paced. Play the current key's voicing correctly
/// and it advances; anything else just flashes. Nothing here rewinds, scores,
/// or watches a clock for timing — the metronome in this mode is a manual
/// click wired to nothing.
///
/// Deliberately absent, compared with `InversionRunController`: no `BeatJudge`,
/// no count-in, no tempo phase, no `RunTally`, no accuracy. A Voicings session
/// keeps the streak alive but is never scored.
///
/// Validation is [VoicingSpec.matches] — octave-agnostic but order-strict, so
/// the shape counts anywhere on the keyboard while a close voicing can never
/// pass for a drop 2.
class VoicingRunController extends ChangeNotifier {
  VoicingRunController({
    required VoicingSpec spec,
    int startPc = 0,
    KeyIncrement increment = KeyIncrement.chromatic,
  }) : _cycle = VoicingCycle(spec, startPc: startPc, increment: increment);

  final VoicingCycle _cycle;

  VoicingCycle get cycle => _cycle;
  VoicingSpec get spec => _cycle.spec;

  /// Fired on every key press before judging (note sound).
  void Function(int midiNote)? onAnyPress;

  /// Fired once when a session ends — completed or stopped early — with the
  /// keys landed and the time spent. The screen uses it to mark practice for
  /// the streak and show a summary. Never carries accuracy: there isn't any.
  void Function(int keysCompleted, Duration elapsed)? onSessionEnd;

  // ---- Drill state -------------------------------------------------------
  bool _running = false;
  bool _complete = false;
  int _stepIndex = 0;
  int _keysCompleted = 0;

  final Set<int> _held = {};
  final Set<int> _wrongFlash = {};
  final Set<int> _correctFlash = {};
  Timer? _flashTimer;

  DateTime? _startedAt;
  Duration _elapsed = Duration.zero;

  // ---- Public state for the UI -------------------------------------------
  bool get running => _running;

  /// Whether the last key of the cycle has been played.
  bool get isComplete => _complete;

  int get stepIndex => _stepIndex;
  int get stepCount => _cycle.length;

  /// Keys landed correctly this session.
  int get keysCompleted => _keysCompleted;

  /// 1-based position for the "7 / 25" readout, held at [stepCount] once done.
  int get stepNumber => _complete ? stepCount : _stepIndex + 1;

  double get progress => stepCount == 0 ? 0 : _stepIndex / stepCount;

  /// The key being drilled. Clamped so a finished session keeps showing its
  /// last key rather than falling off the end of the cycle.
  VoicingStep get currentStep =>
      _cycle.steps[_stepIndex.clamp(0, stepCount - 1)];

  /// Key name for the prompt, e.g. "F#".
  String get keyLabel => currentStep.label;

  /// Degree spelling of the shape, e.g. "7-3-5-1". Constant for the session —
  /// the whole point is that one shape moves through every key.
  String get formulaLabel => spec.formula;

  /// Lowest key the keyboard renders. Fixed for the session (unlike Inversion
  /// Running's transposing keyboard) so the voicing visibly walks up and down.
  int get lowMidi => _cycle.keyboardLow;

  /// Time spent in the current session, frozen once it ends.
  Duration get elapsed => _startedAt == null
      ? _elapsed
      : clock.now().difference(_startedAt!);

  /// Whether the held notes are a correct realisation of the shape in this key.
  bool get currentVoicingHeld => spec.matches(_held, currentStep.keyPc);

  // ---- Start / stop ------------------------------------------------------
  void start() {
    _stepIndex = 0;
    _keysCompleted = 0;
    _complete = false;
    _running = true;
    _held.clear();
    _wrongFlash.clear();
    _correctFlash.clear();
    _flashTimer?.cancel();
    _startedAt = clock.now();
    _elapsed = Duration.zero;
    notifyListeners();
  }

  void stop() => _end();

  /// End the session once, freezing the elapsed time. A no-op when already
  /// idle, so a stop after completion doesn't fire [onSessionEnd] twice.
  void _end() {
    if (!_running) return;
    _elapsed = elapsed;
    _startedAt = null;
    _running = false;
    _clearFlashes();
    onSessionEnd?.call(_keysCompleted, _elapsed);
  }

  // ---- Input (taps + MIDI, identical paths) ------------------------------
  StreamSubscription<MidiNoteEvent>? _midiSub;

  void bindMidi(MidiService service) {
    _midiSub?.cancel();
    _midiSub = service.noteStream.listen((e) {
      if (e.isOn) {
        pressKey(e.note);
      } else {
        releaseKey(e.note);
      }
    });
  }

  void pressKey(int midiNote) {
    onAnyPress?.call(midiNote);
    _held.add(midiNote);
    if (_running) _judgePress(midiNote);
    notifyListeners();
  }

  void releaseKey(int midiNote) {
    _held.remove(midiNote);
    _wrongFlash.remove(midiNote);
    // Lifting a stray finger can leave the correct shape sounding on its own.
    // That counts — the drill advances whenever the shape is right, however
    // the player got there, so a fumble never leaves them stuck.
    if (_running && currentVoicingHeld) _advance();
    notifyListeners();
  }

  /// A press outside the key's chord tones flashes red and is otherwise
  /// ignored: no advance, no rewind, no penalty. A press that could belong to
  /// the shape flashes back, and completing the shape advances. Everything
  /// else — right tones, wrong spacing or wrong bass — simply blocks until the
  /// player fixes it.
  void _judgePress(int midiNote) {
    if (!currentStep.pitchClasses.contains(pitchClassOf(midiNote))) {
      _flash(_wrongFlash, midiNote);
      return;
    }
    _flash(_correctFlash, midiNote);
    if (currentVoicingHeld) _advance();
  }

  void _advance() {
    _keysCompleted++;
    _stepIndex++;
    if (_stepIndex >= stepCount) {
      _complete = true;
      _end();
    }
  }

  void _flash(Set<int> set, int midiNote) {
    set.add(midiNote);
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 350), _clearFlashes);
  }

  void _clearFlashes() {
    _wrongFlash.clear();
    _correctFlash.clear();
    notifyListeners();
  }

  // ---- Keyboard rendering ------------------------------------------------
  KeyFeedback feedbackFor(int midiNote) {
    if (_wrongFlash.contains(midiNote)) return KeyFeedback.wrong;
    if (_correctFlash.contains(midiNote)) return KeyFeedback.correct;
    if (_held.contains(midiNote)) return KeyFeedback.pressed;
    return KeyFeedback.idle;
  }

  /// Target dots: the current key's exact voicing, already octave-folded by
  /// [VoicingCycle] to stay on the keyboard. Matched by MIDI note, not pitch
  /// class, so the dots walk up and back down with the shape.
  bool isTargetHint(int midiNote) => currentStep.notes.contains(midiNote);

  @override
  void dispose() {
    _midiSub?.cancel();
    _flashTimer?.cancel();
    super.dispose();
  }
}
