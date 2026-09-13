/// First-entry guides for each mode: a few lines of copy plus a scripted
/// demo the sheet animates on the player's own instrument surface.
///
/// Demo frames are MIDI notes in C4..C6 (60..84) so the piano can render
/// them directly on a two-octave span; the fretboard maps them by pitch
/// class. Pure data — no Flutter imports — so it stays trivially testable.
library;

/// One guide per home-screen mode. [prefsKey] is the per-device "seen"
/// flag, see QuizSettings.guideSeen.
enum GuideMode {
  freePlay('Free Play', 'guide_seen_free_play'),
  scales('Scales', 'guide_seen_scales'),
  chords('Chords', 'guide_seen_chords'),
  voicings('Voicings', 'guide_seen_voicings'),
  scaleRunning('Scale Running', 'guide_seen_scale_running'),
  inversionRunning('Inversion Running', 'guide_seen_inversion_running'),
  jamMode('Jam Mode', 'guide_seen_jam_mode');

  const GuideMode(this.label, this.prefsKey);

  /// Display name, as on the home screen.
  final String label;

  /// shared_preferences key for the once-per-device flag.
  final String prefsKey;
}

/// One step of a demo: which notes are "sounding" ([lit]), which carry the
/// blue target dot ([hints], defaults to [lit]), how long to hold, and an
/// optional caption shown under the instrument.
class DemoFrame {
  const DemoFrame(
    this.lit, {
    Set<int>? hints,
    this.hold = const Duration(milliseconds: 600),
    this.caption,
  }) : _hints = hints; // ignore: prefer_initializing_formals

  final Set<int> lit;
  final Set<int>? _hints;
  final Duration hold;
  final String? caption;

  Set<int> get hints => _hints ?? lit;
}

class ModeGuide {
  const ModeGuide({
    required this.title,
    required this.lines,
    required this.demo,
  });

  final String title;

  /// 3–4 short numbered lines. Keep each to one sentence.
  final List<String> lines;

  /// Looped by GuideDemo. Never empty.
  final List<DemoFrame> demo;
}

// C4-octave pitch helpers, for readable scripts below.
const _c4 = 60, _db4 = 61, _d4 = 62, _e4 = 64, _f4 = 65, _fs4 = 66, _g4 = 67;
const _gs4 = 68, _a4 = 69, _bb4 = 70, _b4 = 71;
const _c5 = 72, _db5 = 73, _d5 = 74, _e5 = 76, _f5 = 77, _g5 = 79;
const _a5 = 81, _b5 = 83, _c6 = 84;

const _cMajorScale = {_c4, _d4, _e4, _f4, _g4, _a4, _b4, _c5};
const _cChord = {_c4, _e4, _g4};

const Map<GuideMode, ModeGuide> modeGuides = {
  GuideMode.freePlay: ModeGuide(
    title: 'Free Play',
    lines: [
      'Play anything. Whatever is sounding gets named live.',
      'Two notes show the interval, three or more the chord.',
      'The metronome is a plain click here: no scoring, no session.',
    ],
    demo: [
      DemoFrame(
        {_c4, _e4, _g4},
        hold: Duration(milliseconds: 1100),
        caption: 'C Major',
      ),
      DemoFrame(
        {_c4, _e4, _g4, _bb4},
        hold: Duration(milliseconds: 1100),
        caption: 'C7',
      ),
      DemoFrame(
        {_d4, _f4, _a4},
        hold: Duration(milliseconds: 1100),
        caption: 'D Minor',
      ),
      DemoFrame(
        {_c4, _g4},
        hold: Duration(milliseconds: 1100),
        caption: 'Perfect 5th',
      ),
    ],
  ),
  GuideMode.scales: ModeGuide(
    title: 'Scales',
    lines: [
      'A key and scale are named at the top, with its formula.',
      'Play it from the root, one note at a time.',
      'Correct notes light green, wrong ones flash red. Just try again.',
      'Finish the scale to get the next key.',
    ],
    demo: [
      DemoFrame(
        {_c4},
        hints: _cMajorScale,
        hold: Duration(milliseconds: 350),
        caption: 'C Major  1-2-3-4-5-6-7',
      ),
      DemoFrame({_d4}, hints: _cMajorScale, hold: Duration(milliseconds: 350)),
      DemoFrame({_e4}, hints: _cMajorScale, hold: Duration(milliseconds: 350)),
      DemoFrame({_f4}, hints: _cMajorScale, hold: Duration(milliseconds: 350)),
      DemoFrame({_g4}, hints: _cMajorScale, hold: Duration(milliseconds: 350)),
      DemoFrame({_a4}, hints: _cMajorScale, hold: Duration(milliseconds: 350)),
      DemoFrame({_b4}, hints: _cMajorScale, hold: Duration(milliseconds: 350)),
      DemoFrame(
        {_c5},
        hints: _cMajorScale,
        hold: Duration(milliseconds: 900),
        caption: 'Next key…',
      ),
    ],
  ),
  GuideMode.chords: ModeGuide(
    title: 'Chords',
    lines: [
      'Build the named chord, one note at a time or all at once.',
      'Hold it until every note lights up.',
      'The next chord follows straight away.',
    ],
    demo: [
      DemoFrame(
        {_c4},
        hints: _cChord,
        hold: Duration(milliseconds: 400),
        caption: 'C Major',
      ),
      DemoFrame({_c4, _e4}, hints: _cChord, hold: Duration(milliseconds: 400)),
      DemoFrame(_cChord, hold: Duration(milliseconds: 900)),
      DemoFrame(
        {_g4, _b4, _d5},
        hold: Duration(milliseconds: 1000),
        caption: 'G Major',
      ),
      DemoFrame(
        {_f4, _a4, _c5},
        hold: Duration(milliseconds: 1000),
        caption: 'F Major',
      ),
    ],
  ),
  GuideMode.voicings: ModeGuide(
    title: 'Voicings',
    lines: [
      'Capture a chord shape you like by playing it.',
      'Save it, then drill it through all 12 keys.',
      'Tap a saved voicing to run it.',
    ],
    demo: [
      DemoFrame(
        {_c4, _e4, _g4, _b4},
        hold: Duration(milliseconds: 1000),
        caption: 'Your voicing in C',
      ),
      DemoFrame(
        {_db4, _f4, _gs4, _c5},
        hold: Duration(milliseconds: 1000),
        caption: '…in C#',
      ),
      DemoFrame(
        {_d4, _fs4, _a4, _db5},
        hold: Duration(milliseconds: 1000),
        caption: '…in D',
      ),
    ],
  ),
  GuideMode.scaleRunning: ModeGuide(
    title: 'Scale Running',
    lines: [
      'Play the chord on beat one, then run its mode.',
      'One note per click, eight notes per bar.',
      'A one-bar count-in leads into each new key.',
      'Green is on the beat, amber is close, red is off.',
    ],
    demo: [
      DemoFrame(
        {..._cChord, _c5},
        hold: Duration(milliseconds: 350),
        caption: 'Hold C, run C Ionian',
      ),
      DemoFrame({..._cChord, _d5}, hold: Duration(milliseconds: 350)),
      DemoFrame({..._cChord, _e5}, hold: Duration(milliseconds: 350)),
      DemoFrame({..._cChord, _f5}, hold: Duration(milliseconds: 350)),
      DemoFrame({..._cChord, _g5}, hold: Duration(milliseconds: 350)),
      DemoFrame({..._cChord, _a5}, hold: Duration(milliseconds: 350)),
      DemoFrame({..._cChord, _b5}, hold: Duration(milliseconds: 350)),
      DemoFrame(
        {..._cChord, _c6},
        hold: Duration(milliseconds: 700),
        caption: 'Next chord…',
      ),
    ],
  ),
  GuideMode.inversionRunning: ModeGuide(
    title: 'Inversion Running',
    lines: [
      'Play the chord, then walk it up through its inversions and back.',
      'Each inversion is built from scratch, so lift off between them.',
      'In tempo mode, one inversion per beat after the count-in.',
    ],
    demo: [
      DemoFrame(
        {_c4, _e4, _g4},
        hold: Duration(milliseconds: 650),
        caption: 'C Major, root',
      ),
      DemoFrame(
        {_e4, _g4, _c5},
        hold: Duration(milliseconds: 650),
        caption: '1st inversion',
      ),
      DemoFrame(
        {_g4, _c5, _e5},
        hold: Duration(milliseconds: 650),
        caption: '2nd inversion',
      ),
      DemoFrame(
        {_c5, _e5, _g5},
        hold: Duration(milliseconds: 650),
        caption: 'Octave',
      ),
      DemoFrame(
        {_g4, _c5, _e5},
        hold: Duration(milliseconds: 650),
        caption: '2nd inversion',
      ),
      DemoFrame(
        {_e4, _g4, _c5},
        hold: Duration(milliseconds: 650),
        caption: '1st inversion',
      ),
      DemoFrame(
        {_c4, _e4, _g4},
        hold: Duration(milliseconds: 900),
        caption: 'Back to root',
      ),
    ],
  ),
  GuideMode.jamMode: ModeGuide(
    title: 'Jam Mode',
    lines: [
      'One diatonic chord per bar, all in a single key.',
      'Each chord shows during its count-in; strike it on the downbeat.',
      'Any voicing counts, and a slightly late hit still scores.',
    ],
    demo: [
      DemoFrame(
        {_c4, _e4, _g4},
        hold: Duration(milliseconds: 750),
        caption: 'Bar 1 · C',
      ),
      DemoFrame(
        {_f4, _a4, _c5},
        hold: Duration(milliseconds: 750),
        caption: 'Bar 2 · F',
      ),
      DemoFrame(
        {_g4, _b4, _d5},
        hold: Duration(milliseconds: 750),
        caption: 'Bar 3 · G',
      ),
      DemoFrame(
        {_c4, _e4, _g4},
        hold: Duration(milliseconds: 750),
        caption: 'Bar 4 · C',
      ),
    ],
  ),
};
