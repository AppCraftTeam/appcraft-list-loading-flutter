// ignore_for_file: prefer_const_constructors, cascade_invocations
import 'package:appcraft_list_loading_flutter/src/ac_debouncer.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ACDebouncer', () {
    group('construction', () {
      test('defaults to 300ms duration', () {
        // Arrange & Act
        final debouncer = ACDebouncer();

        // Assert
        expect(debouncer.duration, equals(const Duration(milliseconds: 300)));
      });

      test('accepts a custom duration', () {
        // Arrange & Act
        final debouncer = ACDebouncer(const Duration(milliseconds: 750));

        // Assert
        expect(debouncer.duration, equals(const Duration(milliseconds: 750)));
      });

      test('negative duration triggers assertion', () {
        // Arrange & Act & Assert
        expect(
          () => ACDebouncer(const Duration(microseconds: -1)),
          throwsA(isA<AssertionError>()),
        );
      });
    });

    // D1 — trailing-edge: only the last action within the window runs.
    group('D1: trailing-edge', () {
      test('run(a) then run(b) within duration: only b runs after the pause',
          () {
        FakeAsync().run((async) {
          // Arrange
          final debouncer = ACDebouncer(const Duration(milliseconds: 300));
          var aRan = false;
          var bRan = false;

          // Act — schedule a, then replace with b before a fires.
          debouncer.run(() => aRan = true);
          async.elapse(const Duration(milliseconds: 100));
          debouncer.run(() => bRan = true);

          // Assert — nothing fired yet.
          async.elapse(const Duration(milliseconds: 100));
          expect(aRan, isFalse);
          expect(bRan, isFalse);

          // Act — advance past b's window (started at t=100ms).
          async.elapse(const Duration(milliseconds: 200));

          // Assert — only b ran.
          expect(aRan, isFalse,
              reason: 'superseded action must be cancelled');
          expect(bRan, isTrue);
        });
      });
    });

    // D2 — cancel() cancels the pending action, isActive == false.
    group('D2: cancel', () {
      test('run then cancel: nothing runs, isActive is false', () {
        FakeAsync().run((async) {
          // Arrange
          final debouncer = ACDebouncer(const Duration(milliseconds: 300));
          var ran = false;
          debouncer.run(() => ran = true);
          async.elapse(const Duration(milliseconds: 100));

          // Act
          debouncer.cancel();

          // Assert
          expect(debouncer.isActive, isFalse);

          // Elapse well past the would-be firing point.
          async.elapse(const Duration(seconds: 2));
          expect(ran, isFalse, reason: 'cancelled action must not run');
        });
      });

      test('cancel with no pending action is a safe no-op', () {
        // Arrange
        final debouncer = ACDebouncer();

        // Act & Assert
        expect(debouncer.cancel, returnsNormally);
        expect(debouncer.isActive, isFalse);
      });
    });

    // D3 — dispose() cancels the pending action (== cancel).
    group('D3: dispose', () {
      test('run then dispose: nothing runs', () {
        FakeAsync().run((async) {
          // Arrange
          final debouncer = ACDebouncer(const Duration(milliseconds: 300));
          var ran = false;
          debouncer.run(() => ran = true);
          async.elapse(const Duration(milliseconds: 100));

          // Act
          debouncer.dispose();

          // Assert
          expect(debouncer.isActive, isFalse);
          async.elapse(const Duration(seconds: 2));
          expect(ran, isFalse, reason: 'dispose must cancel the pending timer');
        });
      });

      test('dispose is safe on a freshly constructed debouncer', () {
        // Arrange
        final debouncer = ACDebouncer();

        // Act & Assert
        expect(debouncer.dispose, returnsNormally);
      });
    });

    // D5 — a single run(a) fires exactly once after duration.
    group('D5: single run', () {
      test('run(a) fires exactly once after duration', () {
        FakeAsync().run((async) {
          // Arrange
          final debouncer = ACDebouncer(const Duration(milliseconds: 300));
          var count = 0;

          // Act
          debouncer.run(() => count++);

          // Assert — not before the duration elapses.
          async.elapse(const Duration(milliseconds: 299));
          expect(count, equals(0));

          // Act — cross the threshold.
          async.elapse(const Duration(milliseconds: 1));

          // Assert — fired exactly once.
          expect(count, equals(1));

          // Elapse further — must not fire again.
          async.elapse(const Duration(seconds: 2));
          expect(count, equals(1), reason: 'action must run exactly once');
        });
      });
    });

    // D5/isActive — isActive is true while pending, false after firing.
    group('isActive lifecycle', () {
      test('isActive is true while pending and false after firing', () {
        FakeAsync().run((async) {
          // Arrange
          final debouncer = ACDebouncer(const Duration(milliseconds: 300));

          // Assert — nothing scheduled yet.
          expect(debouncer.isActive, isFalse);

          // Act — schedule.
          debouncer.run(() {});

          // Assert — pending.
          expect(debouncer.isActive, isTrue);

          // Act — advance past the window.
          async.elapse(const Duration(milliseconds: 300));

          // Assert — no longer active after firing.
          expect(debouncer.isActive, isFalse);
        });
      });
    });

    // D4 — duration == zero: action runs on the next tick.
    group('D4: zero duration', () {
      test('duration == Duration.zero: action runs on the next tick', () {
        FakeAsync().run((async) {
          // Arrange
          final debouncer = ACDebouncer(Duration.zero);
          var ran = false;

          // Act
          debouncer.run(() => ran = true);

          // Assert — not run synchronously.
          expect(ran, isFalse);
          expect(debouncer.isActive, isTrue);

          // Act — let the event loop advance one tick.
          async.elapse(Duration.zero);

          // Assert
          expect(ran, isTrue);
          expect(debouncer.isActive, isFalse);
        });
      });
    });
  });
}
