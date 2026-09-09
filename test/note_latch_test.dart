import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scale_runner/runner/note_latch.dart';
import 'package:scale_runner/theory/fretboard.dart';

void main() {
  group('NoteLatch', () {
    test('add, toggle and clear', () {
      fakeAsync((async) {
        final l = NoteLatch();
        l.add(60);
        expect(l.toggle(64), isTrue);
        expect(l.notes, {60, 64});
        expect(l.toggle(60), isFalse);
        expect(l.notes, {64});
        expect(l.remove(64), isTrue);
        expect(l.remove(64), isFalse);
        l.add(67);
        l.clear();
        expect(l.isEmpty, isTrue);
        l.dispose();
      });
    });

    test('idle expiry drops the notes and fires onExpire once', () {
      fakeAsync((async) {
        var expired = 0;
        Set<int>? dropped;
        final l = NoteLatch(onExpire: (n) {
          expired++;
          dropped = n;
        });
        l.add(60);
        l.add(64);
        async.elapse(const Duration(milliseconds: 1999));
        expect(l.notes, {60, 64});
        expect(expired, 0);
        async.elapse(const Duration(milliseconds: 1));
        expect(l.isEmpty, isTrue);
        expect(expired, 1);
        expect(dropped, {60, 64});
        async.elapse(const Duration(seconds: 5));
        expect(expired, 1);
        l.dispose();
      });
    });

    test('a new tap restarts the clock; clear and toggling out cancel it', () {
      fakeAsync((async) {
        var expired = 0;
        final l = NoteLatch(onExpire: (_) => expired++);
        l.add(60);
        async.elapse(const Duration(milliseconds: 1500));
        l.add(64);
        async.elapse(const Duration(milliseconds: 1500));
        expect(l.notes, {60, 64});
        async.elapse(const Duration(milliseconds: 500));
        expect(expired, 1);

        l.add(60);
        l.clear();
        async.elapse(const Duration(seconds: 3));
        expect(expired, 1);

        l.add(60);
        l.toggle(60); // nothing left to expire
        async.elapse(const Duration(seconds: 3));
        expect(expired, 1);
        l.dispose();
      });
    });

    test('notes is a copy', () {
      final l = NoteLatch()..add(60);
      l.notes.add(99);
      expect(l.notes, {60});
      l.dispose();
    });
  });

  group('GuitarLatch', () {
    // Standard tuning: string 0 = E2 (40), string 1 = A2 (45), string 2 = D3
    // (50), string 3 = G3 (55), string 4 = B3 (59), string 5 = E4 (64).
    test('a tap replaces the note on its string and reports the change', () {
      final g = GuitarLatch();
      var c = g.tap(const FretPosition(1, 2)); // B2 = 47
      expect(c.on, {47});
      expect(c.off, isEmpty);
      c = g.tap(const FretPosition(1, 3)); // C3 = 48 replaces B2
      expect(c.on, {48});
      expect(c.off, {47});
      expect(g.cells, {const FretPosition(1, 3)});
      expect(g.notes, {48});
    });

    test('a second tap on the same cell puts it out', () {
      final g = GuitarLatch()..tap(const FretPosition(2, 2)); // E3 = 52
      final c = g.tap(const FretPosition(2, 2));
      expect(c.on, isEmpty);
      expect(c.off, {52});
      expect(g.isEmpty, isTrue);
    });

    test('twin positions of one note are neither on nor off', () {
      final g = GuitarLatch()..tap(const FretPosition(3, 4)); // B3 = 59
      var c = g.tap(const FretPosition(4, 0)); // open B, also 59
      expect(c.on, isEmpty);
      expect(c.off, isEmpty);
      expect(g.cells.length, 2);
      c = g.tap(const FretPosition(4, 0)); // out again: 59 still sounds
      expect(c.on, isEmpty);
      expect(c.off, isEmpty);
      c = g.tap(const FretPosition(3, 4));
      expect(c.on, isEmpty);
      expect(c.off, {59});
    });

    test('sync drops cells whose notes the controller let go of', () {
      final g = GuitarLatch()
        ..tap(const FretPosition(0, 3)) // G2 = 43
        ..tap(const FretPosition(1, 2)) // B2 = 47
        ..tap(const FretPosition(2, 0)); // D3 = 50
      g.sync({47});
      expect(g.cells, {const FretPosition(1, 2)});
      g.sync({});
      expect(g.isEmpty, isTrue);
    });
  });
}
