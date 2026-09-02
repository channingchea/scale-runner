/// Pure-Dart fretboard theory for Guitar Mode.
///
/// No UI, no MIDI, no timing — just the map between MIDI notes and places on
/// a neck, and the rules that pick *which* place a drill means. Every
/// guitar-specific ambiguity lives here so the widget can stay a renderer and
/// the controllers can stay untouched.
///
/// Same shape as `music_theory.dart`: fully unit-testable without hardware.
library;

/// Which surface the drills draw and take input from.
enum Instrument {
  piano('Piano'),
  guitar('Guitar');

  const Instrument(this.label);

  /// Display name for settings and labels.
  final String label;

  /// Decode a persisted [Enum.name], falling back to piano for anything
  /// unrecognised (including null, i.e. a fresh install).
  static Instrument byName(String? name) => values.firstWhere(
        (i) => i.name == name,
        orElse: () => Instrument.piano,
      );
}

/// Highest fret the app draws. 22 is the common modern electric; anything
/// above it is out of reach for most players and off the end of many necks.
const int kMaxFret = 22;

/// Frets visible in the portrait chord-diagram box. Five is what fits a phone
/// at a tappable size, and what a chord diagram conventionally shows.
const int kBoxWidth = 5;

/// The widest box [boxFor] will open before giving up on holding every target.
const int kMaxBoxWidth = 6;

/// Highest fret a drill will voluntarily send a shape to. Above this the hand
/// is past the body join on an acoustic and the frets are cramped, so
/// [guitarVoicing] drops an octave instead.
const int kComfortFret = 15;

/// A string's open pitches, low to high.
///
/// Index 0 is the lowest-pitched string — the one a guitarist calls the 6th.
/// The widget flips the drawing order (and flips again for left-handed); the
/// theory here always counts up from the low E so "higher string index" means
/// "higher pitch" everywhere.
class Tuning {
  const Tuning(this.openStrings);

  /// MIDI note of each open string, ascending.
  final List<int> openStrings;

  /// Standard tuning: E1 A1 D2 G2 B2 E3 in MIDI terms (E2-e4 by name).
  static const Tuning standard = Tuning([40, 45, 50, 55, 59, 64]);

  int get stringCount => openStrings.length;

  /// MIDI note sounding at [string] (0-based, low to high) and [fret]
  /// (0 = open).
  int midiAt(int string, int fret) => openStrings[string] + fret;

  /// Lowest note on the instrument (the low open string).
  int get lowest => openStrings.first;

  /// Highest note reachable at [maxFret] on the top string.
  int highest([int maxFret = kMaxFret]) => openStrings.last + maxFret;
}

/// One place on the neck. A MIDI note has several; a position has one note.
class FretPosition {
  const FretPosition(this.string, this.fret);

  /// 0-based, low to high — see [Tuning.openStrings].
  final int string;

  /// 0 is the open string.
  final int fret;

  int midi([Tuning tuning = Tuning.standard]) => tuning.midiAt(string, fret);

  @override
  bool operator ==(Object other) =>
      other is FretPosition && other.string == string && other.fret == fret;

  @override
  int get hashCode => Object.hash(string, fret);

  @override
  String toString() => 'string $string fret $fret';
}

/// The window of frets on screen. Everything a drill highlights has to land
/// inside one of these, because a whole 22-fret neck at phone size is both
/// untappable and unreadable (a 7-note scale paints 84 dots on the full neck
/// and 16 to 18 inside a box).
class FretBox {
  const FretBox(this.start, [this.width = kBoxWidth]);

  /// Lowest fret shown. 0 shows the nut and the open strings.
  final int start;

  /// How many frets are shown, [start] included.
  final int width;

  /// Highest fret shown.
  int get end => start + width - 1;

  bool contains(int fret) => fret >= start && fret <= end;

  /// How far [fret] sits outside the box, 0 when inside.
  int distanceTo(int fret) => fret < start
      ? start - fret
      : fret > end
          ? fret - end
          : 0;

  /// Slide the box so it fits on a neck of [maxFret] frets.
  FretBox clamped({int maxFret = kMaxFret}) {
    final s = start.clamp(0, (maxFret - width + 1).clamp(0, maxFret));
    return s == start ? this : FretBox(s, width);
  }

  @override
  bool operator ==(Object other) =>
      other is FretBox && other.start == start && other.width == width;

  @override
  int get hashCode => Object.hash(start, width);

  @override
  String toString() => 'frets $start-$end';
}

/// A chord shape: one position per note, ascending pitch on ascending
/// strings. What [fit] returns.
class FretShape {
  const FretShape(this.positions);

  /// Aligned with the ascending notes it was built from.
  final List<FretPosition> positions;

  Iterable<int> get frets => positions.map((p) => p.fret);

  int get lowestFret => frets.reduce((a, b) => a < b ? a : b);

  int get highestFret => frets.reduce((a, b) => a > b ? a : b);

  /// Frets between the outermost fingers. 0 means one fret holds everything.
  int get span => highestFret - lowestFret;

  /// The smallest box that shows the whole shape, never narrower than
  /// [kBoxWidth] and never hanging off the end of the neck.
  FretBox box({int maxFret = kMaxFret}) {
    final width = span + 1 < kBoxWidth ? kBoxWidth : span + 1;
    // Centre a wider-than-needed box on the shape rather than jamming it left,
    // so a one-fret chord does not sit against the nut edge of the window.
    final slack = width - (span + 1);
    return FretBox(lowestFret - slack ~/ 2, width).clamped(maxFret: maxFret);
  }

  @override
  String toString() => positions.join(', ');
}

/// Every place [midi] can be played, ordered low string to high.
///
/// One tap is never ambiguous (a cell is exactly one note); it is the display
/// that is one-to-many. Over the piano's 48-72 range a note has 2 to 5
/// positions on a 22-fret neck.
List<FretPosition> positionsFor(
  int midi, {
  Tuning tuning = Tuning.standard,
  int maxFret = kMaxFret,
}) {
  final out = <FretPosition>[];
  for (var s = 0; s < tuning.stringCount; s++) {
    final fret = midi - tuning.openStrings[s];
    if (fret >= 0 && fret <= maxFret) out.add(FretPosition(s, fret));
  }
  return out;
}

/// The single position a drill *means* by [midi] while [box] is on screen.
///
/// In-box wins; among in-box twins the higher string wins, because that is the
/// one nearer the shape a hand is already holding. With nothing in the box
/// (a MIDI keyboard can send anything) the nearest position is returned so the
/// note still lights up somewhere sensible. Null only when the note does not
/// exist on the instrument at all.
FretPosition? primaryFor(
  int midi,
  FretBox box, {
  Tuning tuning = Tuning.standard,
  int maxFret = kMaxFret,
}) {
  final all = positionsFor(midi, tuning: tuning, maxFret: maxFret);
  if (all.isEmpty) return null;
  FretPosition? best;
  var bestDistance = 1 << 30;
  for (final p in all) {
    final d = box.distanceTo(p.fret);
    // `<=` keeps the higher string on a tie, since `all` runs low to high.
    if (d <= bestDistance) {
      bestDistance = d;
      best = p;
    }
  }
  return best;
}

/// The window to open so every note in [targets] is visible.
///
/// Smallest width first (a five-fret box unless the set genuinely needs six),
/// then lowest on the neck. Notes that do not exist on the instrument are
/// ignored rather than making the box impossible. When nothing holds them all,
/// the box that shows the most wins, so the drill degrades instead of
/// blanking.
FretBox boxFor(
  Iterable<int> targets, {
  int width = kBoxWidth,
  int maxWidth = kMaxBoxWidth,
  Tuning tuning = Tuning.standard,
  int maxFret = kMaxFret,
}) {
  final reachable = <List<FretPosition>>[];
  for (final t in targets.toSet()) {
    final ps = positionsFor(t, tuning: tuning, maxFret: maxFret);
    if (ps.isNotEmpty) reachable.add(ps);
  }
  if (reachable.isEmpty) return FretBox(0, width);

  for (var w = width; w <= maxWidth; w++) {
    for (var start = 0; start + w - 1 <= maxFret; start++) {
      final box = FretBox(start, w);
      if (reachable.every((ps) => ps.any((p) => box.contains(p.fret)))) {
        return box;
      }
    }
  }

  var best = FretBox(0, maxWidth);
  var bestCovered = -1;
  for (var start = 0; start + maxWidth - 1 <= maxFret; start++) {
    final box = FretBox(start, maxWidth);
    final covered =
        reachable.where((ps) => ps.any((p) => box.contains(p.fret))).length;
    if (covered > bestCovered) {
      bestCovered = covered;
      best = box;
    }
  }
  return best;
}

/// The string a key's root is measured from when a drill anchors its box.
///
/// The A string. Low E would put the common keys at the nut, where the box
/// cannot show anything below the root; from A, every root lands at fret 3 or
/// higher and the box keeps a fret of room underneath it.
const int kRootAnchorString = 1;

/// The window to open for a whole key, placed at [rootPc]'s own position on
/// the A string.
///
/// For drills that judge by pitch class over a whole scale, the set of lit
/// notes changes every beat, so a box derived from the notes themselves
/// (via [boxFor]) walks around underneath the player. This is derived from
/// the key instead, so it moves when the key moves and not before.
///
/// The root is forced into [minFret]..[maxFret] — an octave up from the nut
/// when it would otherwise sit open — and the box opens one fret below it, so
/// the root sits a finger in rather than against the edge.
FretBox boxAtRoot(
  int rootPc, {
  int string = kRootAnchorString,
  int minFret = 3,
  int maxFret = kComfortFret - 1,
  int width = kBoxWidth,
  Tuning tuning = Tuning.standard,
  int neckFrets = kMaxFret,
}) {
  var fret = (rootPc - tuning.openStrings[string]) % 12;
  while (fret < minFret) {
    fret += 12;
  }
  while (fret > maxFret) {
    fret -= 12;
  }
  final start = fret - 1;
  return FretBox(start < 0 ? 0 : start, width).clamped(maxFret: neckFrets);
}

/// Place [notes] under one hand: one note per string, ascending pitch on
/// ascending strings, everything within [maxSpan] frets of everything else.
///
/// [maxSpan] defaults to 4, which is exactly what a [kBoxWidth] box shows, so
/// a shape that fits is a shape the player can see. Set [adjacentOnly] for
/// Inversion Running, where every voicing is meant to sit on a consecutive
/// string set; leave it off for the Voicings drill, where an open shape like
/// 1-5-10 legitimately skips a string.
///
/// Among the placements that work, the one lowest on the neck wins. Null when
/// the notes cannot be held at all — too many of them, out of range, or
/// spread wider than a hand.
FretShape? fit(
  List<int> notes, {
  bool adjacentOnly = false,
  int maxSpan = kBoxWidth - 1,
  Tuning tuning = Tuning.standard,
  int maxFret = kMaxFret,
}) {
  final sorted = [...notes]..sort();
  if (sorted.isEmpty || sorted.length > tuning.stringCount) return null;

  FretShape? best;
  final chosen = <FretPosition>[];

  void search(int noteIndex, int fromString) {
    if (noteIndex == sorted.length) {
      final shape = FretShape([...chosen]);
      if (shape.span > maxSpan) return;
      if (best == null ||
          shape.highestFret < best!.highestFret ||
          (shape.highestFret == best!.highestFret &&
              shape.lowestFret < best!.lowestFret)) {
        best = shape;
      }
      return;
    }
    // `fromString` is already "one past the string the last note took", so
    // an adjacent-only shape has exactly one candidate per remaining note.
    final highestString = adjacentOnly && chosen.isNotEmpty
        ? fromString
        : tuning.stringCount - 1;
    for (var s = fromString;
        s <= highestString && s < tuning.stringCount;
        s++) {
      final fret = sorted[noteIndex] - tuning.openStrings[s];
      if (fret < 0 || fret > maxFret) continue;
      // Prune early: a partial shape already too wide can only get wider.
      if (chosen.isNotEmpty) {
        final lo = chosen.map((p) => p.fret).reduce((a, b) => a < b ? a : b);
        final hi = chosen.map((p) => p.fret).reduce((a, b) => a > b ? a : b);
        if ((fret > hi ? fret : hi) - (fret < lo ? fret : lo) > maxSpan) {
          continue;
        }
      }
      chosen.add(FretPosition(s, fret));
      search(noteIndex + 1, s + 1);
      chosen.removeLast();
    }
  }

  search(0, 0);
  return best;
}

/// The window to open for one chord shape: the box around the placement
/// [fit] chooses, so what is drawn is a hand and not merely a set of
/// reachable notes.
///
/// [boxFor] only promises each note has *some* position inside the window.
/// For a chord that regularly means two notes stacked on one string — a C
/// maj7 close voicing lands two of its four notes on the high E — which is
/// not a shape anyone can hold. Falls back to [boxFor] when the notes cannot
/// be held at all, so a drill degrades to "reachable" instead of blanking;
/// [fits] is the same question asked on its own, for a screen that wants to
/// say so rather than degrade.
FretBox boxForShape(
  List<int> notes, {
  bool adjacentOnly = false,
  int maxSpan = kBoxWidth - 1,
  Tuning tuning = Tuning.standard,
  int maxFret = kMaxFret,
}) {
  final shape = fit(
    notes,
    adjacentOnly: adjacentOnly,
    maxSpan: maxSpan,
    tuning: tuning,
    maxFret: maxFret,
  );
  return shape?.box(maxFret: maxFret) ??
      boxFor(notes, tuning: tuning, maxFret: maxFret);
}

/// Whether [notes] can be held on the neck at all. See [boxForShape].
bool fits(
  List<int> notes, {
  bool adjacentOnly = false,
  int maxSpan = kBoxWidth - 1,
  Tuning tuning = Tuning.standard,
  int maxFret = kMaxFret,
}) =>
    fit(
      notes,
      adjacentOnly: adjacentOnly,
      maxSpan: maxSpan,
      tuning: tuning,
      maxFret: maxFret,
    ) !=
    null;

/// Textbook drop 2: the second note from the top falls an octave.
///
/// Only meaningful for four notes; anything else is returned sorted and
/// otherwise untouched.
List<int> drop2(List<int> notes) {
  final sorted = [...notes]..sort();
  if (sorted.length != 4) return sorted;
  sorted[2] -= 12;
  sorted.sort();
  return sorted;
}

/// The pitch shape [guitarVoicing] uses, before any octave is chosen:
/// four notes become drop 2 with the bass kept, everything else stays close.
List<int> _guitarShape(List<int> notes) {
  final sorted = [...notes]..sort();
  return sorted.length == 4 ? drop2(_rotateUp(sorted, 2)) : sorted;
}

/// Move the lowest [n] notes up an octave — what a close-position inversion
/// does, expressed as a rotation.
List<int> _rotateUp(List<int> notes, int n) {
  final sorted = [...notes]..sort();
  for (var i = 0; i < n; i++) {
    sorted.sort();
    sorted[0] += 12;
  }
  sorted.sort();
  return sorted;
}

/// The guitar-idiomatic re-voicing of a close-position chord, **keeping its
/// bass note**.
///
/// Triads are already playable close (2 to 3 frets on three adjacent
/// strings). Close four-note chords are not: a close 7th spans 5 to 6 frets,
/// which is why guitarists play drop 2 instead. Dropping the second voice of
/// the close voicing would also change which chord tone is in the bass, and
/// the bass is exactly what Inversion Running validates, so this takes the
/// drop 2 whose bass is unchanged — the close voicing two rotations up, then
/// dropped. That reduces to "the second note from the bottom goes up an
/// octave", so `[a, b, c, d]` becomes `[a, c, d, b + 12]`: C E G B becomes
/// C G B E, the standard drop 2 with the root in the bass.
///
/// The result is then transposed by whole octaves until it fits under a hand
/// at or below [comfortFret]; failing that, until it fits at all. Pitch
/// classes and the bass pitch class survive every step, so nothing about how
/// a drill judges a voicing changes.
List<int> guitarVoicing(
  List<int> notes, {
  Tuning tuning = Tuning.standard,
  int maxFret = kMaxFret,
  int comfortFret = kComfortFret,
  bool adjacentOnly = true,
}) {
  final shape = _guitarShape(notes);

  List<int> shifted(int octaves) => [for (final n in shape) n + octaves * 12];
  FretShape? shapeAt(int octaves) => fit(
        shifted(octaves),
        adjacentOnly: adjacentOnly,
        tuning: tuning,
        maxFret: maxFret,
      );

  // Nearest octave first, then down (a lower shape is the more useful one when
  // the written register runs off the top), then up.
  const order = [0, -1, 1, -2, 2, -3, 3];
  List<int>? fallback;
  var fallbackFret = 1 << 30;
  for (final o in order) {
    final f = shapeAt(o);
    if (f == null) continue;
    if (f.highestFret <= comfortFret) return shifted(o);
    if (f.highestFret < fallbackFret) {
      fallbackFret = f.highestFret;
      fallback = shifted(o);
    }
  }
  // Nothing fits anywhere: hand back the un-transposed shape so callers still
  // have pitch classes to validate against, and let `fit` report the miss.
  return fallback ?? shape;
}

/// Re-voice a whole close-position cycle for guitar at **one shared octave**.
///
/// Choosing each voicing's octave on its own looks right in isolation and is
/// wrong as a sequence. The octave-up root at the apex never fits under a hand
/// where it is written, so it drops back and lands on exactly the same notes
/// as root position — in all 156 chord-and-key cycles Inversion Running can
/// build. The climb the drill exists to teach would disappear.
///
/// Transposing the whole cycle by one offset keeps every interval between
/// steps, so the shape still walks up the neck and back down. The offset is
/// the highest one (nearest the written pitch, so the two instruments stay in
/// the same neighbourhood) where every step fits under a hand at or below
/// [comfortFret]; failing that, the highest where every step merely fits.
///
/// Returns one voicing per entry of [closeVoicings], in the same order.
List<List<int>> guitarVoicingCycle(
  List<List<int>> closeVoicings, {
  Tuning tuning = Tuning.standard,
  int maxFret = kMaxFret,
  int comfortFret = kComfortFret,
  bool adjacentOnly = true,
  int lowestOctave = -4,
  int highestOctave = 2,
}) {
  final shapes = [for (final v in closeVoicings) _guitarShape(v)];
  if (shapes.isEmpty) return const [];

  int? comfortable;
  int? playable;
  for (var o = lowestOctave; o <= highestOctave; o++) {
    var worstFret = 0;
    var allFit = true;
    for (final shape in shapes) {
      final placed = fit(
        [for (final n in shape) n + o * 12],
        adjacentOnly: adjacentOnly,
        tuning: tuning,
        maxFret: maxFret,
      );
      if (placed == null) {
        allFit = false;
        break;
      }
      if (placed.highestFret > worstFret) worstFret = placed.highestFret;
    }
    if (!allFit) continue;
    // Ascending loop, so the last one that passes is the highest.
    playable = o;
    if (worstFret <= comfortFret) comfortable = o;
  }

  final octave = comfortable ?? playable ?? 0;
  return [
    for (final shape in shapes) [for (final n in shape) n + octave * 12],
  ];
}
