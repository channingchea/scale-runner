/// Pure-Dart theory for the Voicings drill.
///
/// No UI, no MIDI, no timing — just one user-built chord shape and the ordered
/// keys it gets drilled through. Fully unit-testable, same pattern as
/// `inversion_running.dart`.
library;

import 'dart:convert';

import 'music_theory.dart';
import 'scale_running.dart' show KeyIncrement;

/// Voicings reuses the shared key-advance enum, so callers only need this
/// library.
export 'scale_running.dart' show KeyIncrement;

// ---------------------------------------------------------------------------
// Shape maths
// ---------------------------------------------------------------------------

/// Above-the-octave relabelling for colour tones voiced 12+ semitones over the
/// root. The structural tones (1 3 5 b7 7) keep their simple names, as do the
/// altered degrees — a b3 an octave up still reads as a b3, not a #9.
const Map<String, String> _compoundLabels = {
  '2': '9', 'b2': 'b9', '4': '11', '#4': '#11', '6': '13', 'b6': 'b13',
};

/// Bass-up degree spelling of a shape from its signed [offsets], e.g.
/// "7-3-5-1" for a Maj7 drop 2 with the 7th in the bass.
///
/// Wraps [formulaOf], which already preserves voicing order and handles the
/// #4/#5/bb7 respellings — and whose `%` is safe for the negative offsets any
/// drop voicing produces. The only thing layered on top is compound
/// relabelling for tones voiced above the octave.
String voicingFormula(List<int> offsets) {
  if (offsets.isEmpty) return '';
  final tokens = formulaOf(offsets).split('-');
  return [
    for (var i = 0; i < tokens.length; i++)
      offsets[i] >= 12 ? _compoundLabels[tokens[i]] ?? tokens[i] : tokens[i],
  ].join('-');
}

/// The MIDI pitch the shape is measured from: **the occurrence of [rootPc]
/// nearest the lowest played note.**
///
/// Picking a root pitch *class* isn't enough to compute offsets — B3-E4-G4-C5
/// called in C is a Maj7 drop 2 (`[-1,4,7,12]`) only if the root is read as C4,
/// not C3. A tritone tie resolves downward, so the bass offset comes out +6
/// rather than −6.
int rootMidiFor(List<int> notes, int rootPc) {
  assert(notes.isNotEmpty, 'rootMidiFor needs at least one note');
  final low = notes.reduce((a, b) => a < b ? a : b);
  final below = low - ((low - rootPc) % 12); // nearest occurrence at or below
  return low - below <= 6 ? below : below + 12;
}

/// Signed semitone offsets of [notes] from [rootPc]'s nearest occurrence,
/// ascending as voiced. Negative values are normal, not an edge case.
List<int> offsetsFrom(List<int> notes, int rootPc) {
  if (notes.isEmpty) return const [];
  final sorted = [...notes]..sort();
  final root = rootMidiFor(sorted, rootPc);
  return [for (final n in sorted) n - root];
}

/// [notes] re-based so the lowest sits at 0 — the interval spacing that
/// matching compares, independent of key and register.
List<int> signatureOf(Iterable<int> notes) {
  final sorted = [...notes]..sort();
  if (sorted.isEmpty) return const [];
  return [for (final n in sorted) n - sorted.first];
}

// ---------------------------------------------------------------------------
// The saved shape
// ---------------------------------------------------------------------------

/// One voicing the user built and named.
///
/// Carries **two** views of the same shape: [offsets] (signed, root-relative)
/// drives the display and the degree formula, [sig] (bass-normalised) drives
/// judging. Storing only one breaks the other.
class VoicingSpec {
  /// Stable id, assigned at save.
  final String id;

  /// User-supplied name. Never empty — Save stays disabled until it isn't.
  final String name;

  /// Pitch class (0–11) the user tapped as the root.
  final int rootPc;

  /// Signed semitones from the root, ascending as voiced. May be negative.
  final List<int> offsets;

  final DateTime createdAt;

  /// Folder this voicing is filed under, or null for Ungrouped. A voicing is
  /// in at most one folder.
  final String? folderId;

  /// Index into `kVoicingTagColors`, or null for no colour tag.
  final int? colorTag;

  /// Ids of the text tags on this voicing. Labels live in the tag library, not
  /// here, so renaming a tag updates every card carrying it.
  final List<String> tagIds;

  const VoicingSpec({
    required this.id,
    required this.name,
    required this.rootPc,
    required this.offsets,
    required this.createdAt,
    this.folderId,
    this.colorTag,
    this.tagIds = const [],
  });

  /// A new spec, stamping [createdAt] and deriving an [id] from it.
  factory VoicingSpec.create({
    required String name,
    required int rootPc,
    required List<int> offsets,
    DateTime? createdAt,
    String? folderId,
    int? colorTag,
    List<String> tagIds = const [],
  }) {
    final at = createdAt ?? DateTime.now();
    return VoicingSpec(
      id: 'v${at.microsecondsSinceEpoch}',
      name: name,
      rootPc: rootPc % 12,
      offsets: offsets,
      createdAt: at,
      folderId: folderId,
      colorTag: colorTag,
      tagIds: tagIds,
    );
  }

  /// Build a spec straight from played [notes] and the chosen root.
  factory VoicingSpec.fromNotes({
    required String name,
    required int rootPc,
    required List<int> notes,
    DateTime? createdAt,
  }) =>
      VoicingSpec.create(
        name: name,
        rootPc: rootPc,
        offsets: offsetsFrom(notes, rootPc % 12),
        createdAt: createdAt,
      );

  /// [offsets] re-based so the bass is 0 — the matching signature.
  List<int> get sig =>
      offsets.isEmpty ? const [] : [for (final o in offsets) o - offsets.first];

  /// Semitones from the lowest voice to the highest.
  int get span => offsets.isEmpty ? 0 : offsets.last - offsets.first;

  int get noteCount => offsets.length;

  /// Degree spelling, read bass up.
  String get formula => voicingFormula(offsets);

  /// Name of the root pitch class, e.g. "C".
  String get rootName => pitchClassNames[rootPc];

  /// Pitch class that has to be in the bass when the shape is played in
  /// [keyPc] — the chord tone the voicing puts on the bottom, transposed.
  int bassPcIn(int keyPc) => (keyPc + offsets.first) % 12;

  /// The shape's MIDI notes with its root at [rootMidi], ascending.
  List<int> notesFrom(int rootMidi) => [for (final o in offsets) rootMidi + o];

  /// The shape as playable notes on a [low]–[high] keyboard — the inverse of
  /// capture, so the edit screen can put a saved voicing back under the user's
  /// fingers. Uses the drill's own octave-fold rule, so editing a shape shows
  /// it where the drill would.
  List<int> playableNotes({
    int low = kVoicingKeyboardLow,
    int high = kVoicingKeyboardHigh,
  }) =>
      notesFrom(_fitRoot(_baseRoot(offsets, rootPc, low), offsets, low, high));

  /// Whether [held] is a correct realisation of this shape in [keyPc]:
  /// identical interval spacing **and** the right chord tone in the bass.
  ///
  /// Octave-agnostic (the shape counts anywhere on the keyboard) but
  /// order-strict (a close voicing can never pass for a drop 2).
  bool matches(Iterable<int> held, int keyPc) {
    if (offsets.isEmpty) return false;
    final sorted = [...held]..sort();
    if (sorted.length != offsets.length) return false;
    if (sorted.first % 12 != bassPcIn(keyPc)) return false;
    for (var i = 0; i < sorted.length; i++) {
      if (sorted[i] - sorted.first != offsets[i] - offsets.first) return false;
    }
    return true;
  }

  /// Whether [other] would drill identically: same spacing, the same chord
  /// tone in the bass, the same root. Two captures of one shape an octave
  /// apart count as the same voicing, because the drill can't tell them apart
  /// either. Used to warn — never to block — on a duplicate save.
  bool sameShapeAs(VoicingSpec other) {
    if (offsets.isEmpty || other.offsets.isEmpty) return false;
    return rootPc == other.rootPc &&
        offsets.first % 12 == other.offsets.first % 12 &&
        _sameInts(sig, other.sig);
  }

  /// A copy with fields replaced. [folderId] and [colorTag] are nullable
  /// *values*, so clearing them needs the explicit [clearFolder] /
  /// [clearColor] flags — passing null just means "leave it alone".
  VoicingSpec copyWith({
    String? name,
    int? rootPc,
    List<int>? offsets,
    String? folderId,
    bool clearFolder = false,
    int? colorTag,
    bool clearColor = false,
    List<String>? tagIds,
  }) =>
      VoicingSpec(
        id: id,
        name: name ?? this.name,
        rootPc: rootPc ?? this.rootPc,
        offsets: offsets ?? this.offsets,
        createdAt: createdAt,
        folderId: clearFolder ? null : (folderId ?? this.folderId),
        colorTag: clearColor ? null : (colorTag ?? this.colorTag),
        tagIds: tagIds ?? this.tagIds,
      );

  /// JSON line for SharedPreferences. JSON rather than the pipe-delimited
  /// format used elsewhere because [name] is free user text.
  String encode() => jsonEncode({
        'id': id,
        'name': name,
        'root': rootPc,
        'offsets': offsets,
        'at': createdAt.microsecondsSinceEpoch,
        if (folderId != null) 'folder': folderId,
        if (colorTag != null) 'color': colorTag,
        if (tagIds.isNotEmpty) 'tags': tagIds,
      });

  /// Inverse of [encode]. Returns null on anything malformed so one bad line
  /// can't take the whole collection down.
  static VoicingSpec? decode(String line) {
    try {
      final m = jsonDecode(line);
      if (m is! Map) return null;
      final offsets = [for (final o in m['offsets'] as List) o as int];
      final id = m['id'] as String;
      final root = m['root'] as int;
      final at = m['at'] as int;
      if (offsets.isEmpty || id.isEmpty) return null;
      return VoicingSpec(
        id: id,
        name: m['name'] as String,
        rootPc: root % 12,
        offsets: offsets,
        createdAt: DateTime.fromMicrosecondsSinceEpoch(at),
        folderId: m['folder'] as String?,
        colorTag: m['color'] as int?,
        tagIds: [
          for (final t in (m['tags'] as List? ?? const [])) t as String,
        ],
      );
    } catch (_) {
      return null;
    }
  }
}

// ---------------------------------------------------------------------------
// Folders and tags
// ---------------------------------------------------------------------------

/// A named record with a stable id, ordered by its place in the stored list.
///
/// Folders and text tags hold exactly the same data and differ only in what
/// they mean, so they share one class rather than two identical ones. Both are
/// referenced from [VoicingSpec] by id, never by name — that's what makes a
/// rename update every card at once.
class VoicingLabel {
  final String id;
  final String name;

  const VoicingLabel(this.id, this.name);

  /// A new record with an id derived from the clock. [prefix] keeps folder and
  /// tag ids visually distinct in stored JSON ('f' / 't').
  factory VoicingLabel.create(String name, {String prefix = 'f'}) =>
      VoicingLabel('$prefix${DateTime.now().microsecondsSinceEpoch}', name);

  VoicingLabel renamed(String newName) => VoicingLabel(id, newName);

  String encode() => jsonEncode({'id': id, 'name': name});

  /// Null on anything malformed, so one bad line can't take the list down.
  static VoicingLabel? decode(String line) {
    try {
      final m = jsonDecode(line);
      if (m is! Map) return null;
      final id = m['id'] as String;
      if (id.isEmpty) return null;
      return VoicingLabel(id, m['name'] as String);
    } catch (_) {
      return null;
    }
  }
}

/// A folder in the Voicings list. A voicing is in at most one.
typedef VoicingFolder = VoicingLabel;

/// A reusable text tag. Many per voicing.
typedef VoicingTag = VoicingLabel;

/// [all] regrouped into display order: each folder's members in their existing
/// relative order, folder by folder, then everything unfiled.
///
/// The flat list is the one source of order, so grouping it this way is what
/// makes a section a contiguous slice — which is what lets a drag inside a
/// section be a plain move inside this list.
///
/// A voicing pointing at a folder that no longer exists falls through to
/// Ungrouped rather than vanishing.
List<VoicingSpec> groupVoicings(
    List<VoicingSpec> all, List<VoicingFolder> folders) {
  final ids = {for (final f in folders) f.id};
  return [
    for (final f in folders) ...all.where((v) => v.folderId == f.id),
    ...all.where((v) => v.folderId == null || !ids.contains(v.folderId)),
  ];
}

/// Whether [spec] matches a search box holding [query]: a case-insensitive
/// substring of its name, of any of its [tagLabels], or of [folderName].
///
/// Labels are passed in rather than looked up, because ids only become names
/// through the tag library the caller owns.
bool voicingMatchesQuery(
  VoicingSpec spec,
  String query, {
  List<String> tagLabels = const [],
  String? folderName,
}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  if (spec.name.toLowerCase().contains(q)) return true;
  if (tagLabels.any((l) => l.toLowerCase().contains(q))) return true;
  return folderName != null && folderName.toLowerCase().contains(q);
}

// ---------------------------------------------------------------------------
// The drill cycle
// ---------------------------------------------------------------------------

/// Default keyboard for the mode: 3 octaves, C3–C6.
const int kVoicingKeyboardLow = 48;
const int kVoicingKeyboardHigh = 84;

/// One key of the drill: the shape transposed into [keyPc] at a register that
/// fits the keyboard.
class VoicingStep {
  /// Pitch class (0–11) of this step's key.
  final int keyPc;

  /// Exact MIDI notes to highlight (target dots), ascending.
  final List<int> notes;

  /// Display label — the key name, e.g. "F#".
  final String label;

  const VoicingStep({
    required this.keyPc,
    required this.notes,
    required this.label,
  });

  /// Pitch class the bass must have. [notes] is ascending, so it's the first.
  int get bassPc => notes.first % 12;

  /// Pitch classes this step's shape uses. Matching is stricter than this (see
  /// [VoicingSpec.matches]); it's what flags a press that can't be part of any
  /// correct answer in this key.
  Set<int> get pitchClasses => {for (final n in notes) n % 12};
}

/// One voicing walked through every key.
///
/// - **Chromatic** — ascend +0…+12, then descend +11…+0. Apex played once:
///   **25 steps.**
/// - **Fifths** — always up a perfect 5th, 12 keys, no separate descent.
///
/// Register climbs with the key so the shape visibly walks up and back down.
/// When it would run off the top the anchor drops an octave; matching ignores
/// register, so a folded step still counts.
class VoicingCycle {
  final VoicingSpec spec;

  /// Pitch class (0–11) the drill starts in.
  final int startPc;

  final KeyIncrement increment;
  final int keyboardLow;
  final int keyboardHigh;

  /// Ordered keys of the session.
  final List<VoicingStep> steps;

  VoicingCycle._(
    this.spec,
    this.startPc,
    this.increment,
    this.keyboardLow,
    this.keyboardHigh,
    this.steps,
  );

  factory VoicingCycle(
    VoicingSpec spec, {
    int startPc = 0,
    KeyIncrement increment = KeyIncrement.chromatic,
    int keyboardLow = kVoicingKeyboardLow,
    int keyboardHigh = kVoicingKeyboardHigh,
  }) {
    final start = startPc % 12;
    // Semitone distance of each step from the starting key. Cumulative, not
    // mod 12 — that's what makes the register climb.
    final advances = increment == KeyIncrement.chromatic
        ? [for (var i = 0; i <= 12; i++) i, for (var i = 11; i >= 0; i--) i]
        : [for (var i = 0; i < 12; i++) i * 7];
    final base = _baseRoot(spec.offsets, start, keyboardLow);
    final steps = [
      for (final a in advances)
        _stepAt(spec, base + a, keyboardLow, keyboardHigh),
    ];
    return VoicingCycle._(
        spec, start, increment, keyboardLow, keyboardHigh, steps);
  }

  int get length => steps.length;

  /// "{name} · {root} {formula}", e.g. "My drop 2 · C 7-3-5-1".
  String get label => '${spec.name} · ${spec.rootName} ${spec.formula}';

  static VoicingStep _stepAt(VoicingSpec spec, int root, int low, int high) {
    final fitted = _fitRoot(root, spec.offsets, low, high);
    return VoicingStep(
      keyPc: fitted % 12,
      notes: spec.notesFrom(fitted),
      label: pitchClassNames[fitted % 12],
    );
  }
}

// ---------------------------------------------------------------------------
// Keyboard placement
// ---------------------------------------------------------------------------
// Shared by the drill cycle and by [VoicingSpec.playableNotes], so a shape
// lands in the same register whether you're editing it or playing it.

/// Lowest occurrence of [rootPc] that keeps the whole shape on the keyboard.
int _baseRoot(List<int> offsets, int rootPc, int low) {
  var root = rootPc % 12;
  while (root + offsets.first < low) {
    root += 12;
  }
  return root;
}

/// Shift [root] by octaves until the shape fits between [low] and [high].
/// Folding stops rather than pushing the shape off the other end, so a voicing
/// wider than the keyboard still yields a placement (it just can't fit).
int _fitRoot(int root, List<int> offsets, int low, int high) {
  final lowOff = offsets.first;
  final highOff = offsets.last;
  var r = root;
  while (r + highOff > high && r - 12 + lowOff >= low) {
    r -= 12;
  }
  while (r + lowOff < low && r + 12 + highOff <= high) {
    r += 12;
  }
  return r;
}

bool _sameInts(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
