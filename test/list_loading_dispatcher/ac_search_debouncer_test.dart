// ignore_for_file: prefer_const_constructors, cascade_invocations
import 'package:appcraft_list_loading_flutter/src/ac_search_debouncer.dart';
import 'package:appcraft_list_loading_flutter/src/ac_search_strategy.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ACSearchDebouncer', () {
    group('construction', () {
      test('defaults: minLength=3', () {
        // Arrange & Act
        final strategy = ACSearchDebouncer();

        // Assert
        expect(strategy.minLength, equals(3));
      });

      test('accepts a custom minLength', () {
        // Arrange & Act
        final strategy = ACSearchDebouncer(minLength: 5);

        // Assert
        expect(strategy.minLength, equals(5));
      });

      test('negative debounce triggers assertion', () {
        // Arrange & Act & Assert
        expect(
          () => ACSearchDebouncer(
            debounce: const Duration(microseconds: -1),
          ),
          throwsA(isA<AssertionError>()),
        );
      });

      test('negative minLength triggers assertion', () {
        // Arrange & Act & Assert
        expect(
          () => ACSearchDebouncer(minLength: -1),
          throwsA(isA<AssertionError>()),
        );
      });

      test('is an ACSearchStrategy', () {
        // Arrange
        final strategy = ACSearchDebouncer();

        // Act & Assert
        expect(strategy, isA<ACSearchStrategy>());
      });
    });

    // S1 — empty / null query launches immediately and resets last-applied.
    group('S1: empty / null query', () {
      test('query == null returns an immediately-completing Future', () {
        FakeAsync().run((async) {
          // Arrange
          final strategy = ACSearchDebouncer();

          // Act
          final future = strategy.schedule(null);
          var completed = false;
          future!.then((_) => completed = true);
          async.flushMicrotasks();

          // Assert
          expect(future, isNotNull);
          expect(completed, isTrue,
              reason: 'null query must complete without any time elapsing');
        });
      });

      test('empty query returns an immediately-completing Future', () {
        FakeAsync().run((async) {
          // Arrange
          final strategy = ACSearchDebouncer();

          // Act
          final future = strategy.schedule('');
          var completed = false;
          future!.then((_) => completed = true);
          async.flushMicrotasks();

          // Assert
          expect(future, isNotNull);
          expect(completed, isTrue);
        });
      });

      test('null-query schedule resets last-applied so a subsequent '
          'valid query is debounced again', () {
        FakeAsync().run((async) {
          // Arrange — prime the strategy by applying 'john' through debounce.
          final strategy = ACSearchDebouncer();
          var firstApplied = false;
          strategy.schedule('john')!.then((_) => firstApplied = true);
          async.elapse(const Duration(milliseconds: 300));
          async.flushMicrotasks();
          expect(firstApplied, isTrue);

          // Act 1 — schedule null; must reset last-applied.
          var nullApplied = false;
          strategy.schedule(null)!.then((_) => nullApplied = true);
          async.flushMicrotasks();
          expect(nullApplied, isTrue);

          // Act 2 — schedule 'john' again; must now debounce again because
          // the previous null reset cleared the tracked query.
          var secondApplied = false;
          strategy.schedule('john')!.then((_) => secondApplied = true);
          async.elapse(const Duration(milliseconds: 100));
          async.flushMicrotasks();

          // Assert — before debounce fires, nothing completed yet.
          expect(secondApplied, isFalse,
              reason: 'null reset must require re-debouncing the old query');

          // Advance the remaining debounce — completes now.
          async.elapse(const Duration(milliseconds: 300));
          async.flushMicrotasks();
          expect(secondApplied, isTrue);
        });
      });
    });

    // S2 — query shorter than minLength is rejected (null return).
    group('S2: minLength rejection', () {
      test('query shorter than minLength returns null', () {
        // Arrange
        final strategy = ACSearchDebouncer();

        // Act
        final future = strategy.schedule('ab');

        // Assert
        expect(future, isNull,
            reason: 'short query must signal rejection via null return');
      });

      test('query shorter than custom minLength returns null', () {
        // Arrange
        final strategy = ACSearchDebouncer(minLength: 5);

        // Act
        final future = strategy.schedule('ab');

        // Assert
        expect(future, isNull);
      });

      test('query at exactly minLength is accepted (boundary)', () {
        FakeAsync().run((async) {
          // Arrange — minLength=3, 'abc' is length 3.
          final strategy = ACSearchDebouncer();

          // Act
          final future = strategy.schedule('abc');

          // Assert
          expect(future, isNotNull,
              reason: 'length == minLength must be accepted');

          // Drain any pending debounce so FakeAsync doesn't complain about
          // pending timers.
          async.elapse(const Duration(seconds: 1));
          async.flushMicrotasks();
        });
      });
    });

    // S3/S4/S5/S6 — repeated / changed query timing.
    group('schedule: repeated / changed query', () {
      test('S3: repeating the last-applied query completes immediately '
          '(no debounce)', () {
        FakeAsync().run((async) {
          // Arrange — first apply 'john' through debounce.
          final strategy = ACSearchDebouncer();
          var firstApplied = false;
          strategy.schedule('john')!.then((_) => firstApplied = true);
          async.elapse(const Duration(milliseconds: 300));
          async.flushMicrotasks();
          expect(firstApplied, isTrue);

          // Act — same query again.
          var secondApplied = false;
          strategy.schedule('john')!.then((_) => secondApplied = true);
          async.flushMicrotasks();

          // Assert — completes without any time elapsing.
          expect(secondApplied, isTrue,
              reason: 'repeated query must bypass debounce');
        });
      });

      test('S5: changed query with length >= minLength waits for the debounce '
          'timer before completing', () {
        FakeAsync().run((async) {
          // Arrange
          final strategy = ACSearchDebouncer(
            debounce: const Duration(milliseconds: 300),
          );

          // Act — schedule; nothing completes until debounce elapses.
          var applied = false;
          strategy.schedule('john')!.then((_) => applied = true);
          async.elapse(const Duration(milliseconds: 100));
          async.flushMicrotasks();

          // Assert — debounce not yet elapsed.
          expect(applied, isFalse);

          // Act — advance past the remaining debounce.
          async.elapse(const Duration(milliseconds: 300));
          async.flushMicrotasks();

          // Assert
          expect(applied, isTrue);
        });
      });

      test('S4: Duration.zero debounce — changed query completes immediately',
          () {
        FakeAsync().run((async) {
          // Arrange
          final strategy = ACSearchDebouncer(
            debounce: Duration.zero,
          );

          // Act
          var applied = false;
          strategy.schedule('john')!.then((_) => applied = true);
          async.flushMicrotasks();

          // Assert — completes without any fake time elapsing.
          expect(applied, isTrue);
        });
      });

      test('S6: schedule twice within debounce window — first timer is '
          'cancelled via the shared debouncer, only second completes', () {
        FakeAsync().run((async) {
          // Arrange
          final strategy = ACSearchDebouncer(
            debounce: const Duration(milliseconds: 300),
          );

          // Act — first schedule starts a timer.
          var firstApplied = false;
          strategy.schedule('joh')!.then((_) => firstApplied = true);
          async.elapse(const Duration(milliseconds: 100));

          // Replace with a different query before the first timer fires.
          var secondApplied = false;
          strategy.schedule('john')!.then((_) => secondApplied = true);

          // Elapse enough for the FIRST timer's original 300ms budget
          // (total 400ms) — but the first timer was cancelled, so still
          // nothing completes.
          async.elapse(const Duration(milliseconds: 200));
          async.flushMicrotasks();

          // Assert — the second timer's 300ms started at t=100ms; now at
          // t=300ms it elapses at t=400ms.
          expect(firstApplied, isFalse,
              reason: 'superseded first timer must be cancelled');
          expect(secondApplied, isFalse,
              reason: 'second timer still pending');

          // Elapse the rest of the second timer's debounce.
          async.elapse(const Duration(milliseconds: 100));
          async.flushMicrotasks();

          // Assert — only the second completed.
          expect(firstApplied, isFalse,
              reason: 'first future never resolves after being superseded');
          expect(secondApplied, isTrue);
        });
      });

      test('schedule after minLength rejection: new valid query is still '
          'debounced', () {
        FakeAsync().run((async) {
          // Arrange
          final strategy = ACSearchDebouncer();

          // Act 1 — short query returns null (rejected).
          final rejected = strategy.schedule('ab');
          expect(rejected, isNull);

          // Act 2 — valid query must still debounce.
          var applied = false;
          strategy.schedule('abcd')!.then((_) => applied = true);
          async.elapse(const Duration(milliseconds: 100));
          async.flushMicrotasks();
          expect(applied, isFalse);

          async.elapse(const Duration(milliseconds: 300));
          async.flushMicrotasks();

          // Assert
          expect(applied, isTrue);
        });
      });
    });

    // S7 — cancel / dispose delegate to the shared debouncer.
    group('S7: cancel', () {
      test('cancel() cancels a pending timer: future never completes', () {
        FakeAsync().run((async) {
          // Arrange
          final strategy = ACSearchDebouncer();
          var applied = false;
          strategy.schedule('john')!.then((_) => applied = true);
          async.elapse(const Duration(milliseconds: 100));

          // Act
          strategy.cancel();

          // Elapse well past where the timer would have fired.
          async.elapse(const Duration(seconds: 2));
          async.flushMicrotasks();

          // Assert — future never completed.
          expect(applied, isFalse, reason: 'cancelled timer must not fire');
        });
      });

      test('cancel() with no pending timer is a safe no-op', () {
        // Arrange
        final strategy = ACSearchDebouncer();

        // Act & Assert — must not throw.
        expect(strategy.cancel, returnsNormally);
        expect(strategy.cancel, returnsNormally);
      });
    });

    group('S7: dispose', () {
      test('dispose() cancels a pending timer: future never completes', () {
        FakeAsync().run((async) {
          // Arrange
          final strategy = ACSearchDebouncer();
          var applied = false;
          strategy.schedule('john')!.then((_) => applied = true);
          async.elapse(const Duration(milliseconds: 100));

          // Act
          strategy.dispose();

          // Elapse past the would-be firing point.
          async.elapse(const Duration(seconds: 2));
          async.flushMicrotasks();

          // Assert
          expect(applied, isFalse,
              reason: 'dispose must cancel the pending debounce timer');
        });
      });

      test('dispose() is safe on a freshly constructed strategy', () {
        // Arrange
        final strategy = ACSearchDebouncer();

        // Act & Assert
        expect(strategy.dispose, returnsNormally);
      });
    });
  });
}
