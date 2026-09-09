/// The metronome's time signature.
///
/// [none] is today's plain click: every tick alike, and drills keep their
/// four-beat count-in. Any other meter accents beat 1 of each bar with a
/// higher click and a stronger haptic; every other beat is the normal click
/// (no secondary accents). BPM always means clicks per minute, so in 5/8 and
/// 6/8 each click is an eighth note.
enum Meter {
  none(4, 'No accent'),
  threeFour(3, '3/4'),
  fourFour(4, '4/4'),
  fiveEight(5, '5/8'),
  sixEight(6, '6/8');

  const Meter(this.beatsPerBar, this.label);

  /// Clicks per bar. Drills use it for their count-in and, in Jam Mode, for
  /// the length of each chord.
  final int beatsPerBar;

  /// Picker label.
  final String label;

  /// Whether beat 1 sounds different from the rest.
  bool get accents => this != none;

  /// 5/8 and 6/8 click eighth notes, so 120 BPM is a dotted-quarter pulse of
  /// 40 in 6/8. The picker says so under those two.
  bool get clicksEighths => this == fiveEight || this == sixEight;

  /// The persisted form is the enum name; anything unknown reads as [none].
  static Meter fromName(String? name) =>
      values.firstWhere((m) => m.name == name, orElse: () => none);
}
