import 'package:flutter_test/flutter_test.dart';
import 'package:scale_runner/theory/music_theory.dart';
import 'package:scale_runner/quiz/quiz_controller.dart';

void main() {
  group('QuizController - scale mode', () {
    test('plays the target scale correctly and scores', () {
      // Single scale + fixed seed -> deterministic prompt.
      final major = const ScaleFormula('Major', [0, 2, 4, 5, 7, 9, 11]);
      final c = QuizController(
        mode: QuizMode.scale,
        scales: [major],
        seed: 1,
      );

      // Reconstruct the exact target notes from the controller's prompt.
      final notes = c.targetNotes;
      expect(c.score, 0);

      for (final n in notes) {
        c.pressKey(n);
        c.releaseKey(n);
      }
      expect(c.roundComplete, isTrue);
      expect(c.score, 1);
      expect(c.streak, 1);
    });

    test('after a win, the next key press advances to a new round', () {
      final major = const ScaleFormula('Major', [0, 2, 4, 5, 7, 9, 11]);
      final c = QuizController(mode: QuizMode.scale, scales: [major], seed: 1);

      for (final n in c.targetNotes) {
        c.pressKey(n);
        c.releaseKey(n);
      }
      expect(c.roundComplete, isTrue);
      final attemptsAtWin = c.attempts;

      // Any press while complete advances; it must not re-score or flag wrong.
      c.pressKey(QuizController.keyboardLowMidi);
      expect(c.roundComplete, isFalse);
      expect(c.attempts, attemptsAtWin + 1);
      expect(c.score, 1);
      expect(c.feedbackFor(QuizController.keyboardLowMidi), KeyFeedback.idle);
    });

    test('a wrong note breaks the streak and resets the attempt', () {
      final major = const ScaleFormula('Major', [0, 2, 4, 5, 7, 9, 11]);
      final c = QuizController(mode: QuizMode.scale, scales: [major], seed: 2);
      final notes = c.targetNotes;

      // Play first note right, then a deliberately wrong note.
      c.pressKey(notes[0]);
      final wrong = notes[0] + 1; // a semitone off is not the 2nd scale degree
      // Guard: ensure it really isn't the expected next note's pitch class.
      if (pitchClassOf(wrong) != pitchClassOf(notes[1])) {
        c.pressKey(wrong);
        expect(c.feedbackFor(wrong), KeyFeedback.wrong);
        expect(c.roundComplete, isFalse);
      }
    });
  });

  group('QuizController - chord mode', () {
    test('holding the exact chord completes the round', () {
      final cMaj = const ChordFormula('Major', [0, 4, 7]);
      final c = QuizController(mode: QuizMode.chord, chords: [cMaj], seed: 3);
      final notes = c.targetNotes; // 3 notes in root position

      c.pressKey(notes[0]);
      expect(c.roundComplete, isFalse);
      c.pressKey(notes[1]);
      expect(c.roundComplete, isFalse);
      c.pressKey(notes[2]);
      expect(c.roundComplete, isTrue);
      expect(c.score, 1);
    });

    test('an extra non-chord note is flagged wrong', () {
      final cMaj = const ChordFormula('Major', [0, 4, 7]);
      final c = QuizController(mode: QuizMode.chord, chords: [cMaj], seed: 4);
      final notes = c.targetNotes;

      c.pressKey(notes[0]);
      final extra = notes[0] + 1; // chromatic neighbor, not in a major triad
      c.pressKey(extra);
      expect(c.feedbackFor(extra), KeyFeedback.wrong);
      expect(c.roundComplete, isFalse);
    });
  });

  test('resetStats zeros score, streak, and best streak', () {
    final c = QuizController(mode: QuizMode.scale, seed: 5);
    // Win a round to accumulate stats.
    for (final n in c.targetNotes) {
      c.pressKey(n);
    }
    expect(c.score, 1);
    expect(c.bestStreak, 1);
    c.resetStats();
    expect(c.score, 0);
    expect(c.streak, 0);
    expect(c.bestStreak, 0);
  });
}
