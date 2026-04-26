import 'dart:async';

import 'package:appcraft_list_loading_flutter/src/ac_cancel_strategy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ACOperationCancelStrategy', () {
    group('isActive', () {
      test('is false on a freshly constructed instance', () {
        // Arrange & Act
        final strategy = ACOperationCancelStrategy();

        // Assert
        expect(strategy.isActive, isFalse);
      });

      test('is false after successful completion', () async {
        // Arrange
        final strategy = ACOperationCancelStrategy();

        // Act
        await strategy.run<int>(Future<int>.value(42));

        // Assert
        expect(strategy.isActive, isFalse);
      });

      test('is false after cancellation', () async {
        // Arrange
        final strategy = ACOperationCancelStrategy();
        final completer = Completer<int>();

        // Act
        final runFuture = strategy.run<int>(completer.future);
        await strategy.cancel();
        await runFuture;

        // Assert
        expect(strategy.isActive, isFalse);
      });
    });

    group('run', () {
      test('returns the future value on successful completion', () async {
        // Arrange
        final strategy = ACOperationCancelStrategy();

        // Act
        final result = await strategy.run<int>(Future<int>.value(42));

        // Assert
        expect(result, equals(42));
      });

      test('returns the future value for a delayed future', () async {
        // Arrange
        final strategy = ACOperationCancelStrategy();
        final delayed = Future<String>.delayed(
          const Duration(milliseconds: 10),
          () => 'done',
        );

        // Act
        final result = await strategy.run<String>(delayed);

        // Assert
        expect(result, equals('done'));
      });

      test('returns null when cancel() is called before completion', () async {
        // Arrange
        final strategy = ACOperationCancelStrategy();
        final completer = Completer<int>();

        // Act
        final runFuture = strategy.run<int>(completer.future);
        await strategy.cancel();
        final result = await runFuture;

        // Assert
        expect(result, isNull);
      });

      test('preserves the original generic type for value results', () async {
        // Arrange
        final strategy = ACOperationCancelStrategy();

        // Act
        final result = await strategy.run<List<int>>(
          Future<List<int>>.value(<int>[1, 2, 3]),
        );

        // Assert
        expect(result, isA<List<int>?>());
        expect(result, equals(<int>[1, 2, 3]));
      });
    });

    group('cancel', () {
      test('is safe to call before run()', () async {
        // Arrange
        final strategy = ACOperationCancelStrategy();

        // Act & Assert
        await expectLater(strategy.cancel(), completes);
      });

      test('is safe to call after successful completion', () async {
        // Arrange
        final strategy = ACOperationCancelStrategy();
        await strategy.run<int>(Future<int>.value(1));

        // Act & Assert
        await expectLater(strategy.cancel(), completes);
      });

      test('repeated cancel() calls are no-ops (no exception)', () async {
        // Arrange
        final strategy = ACOperationCancelStrategy();
        final completer = Completer<int>();
        final runFuture = strategy.run<int>(completer.future);

        // Act
        await strategy.cancel();

        // Assert
        await expectLater(strategy.cancel(), completes);
        await expectLater(strategy.cancel(), completes);
        await runFuture;
      });

      test('cancel() after cancellation is safe', () async {
        // Arrange
        final strategy = ACOperationCancelStrategy();
        final completer = Completer<int>();
        final runFuture = strategy.run<int>(completer.future);
        await strategy.cancel();
        await runFuture;

        // Act & Assert
        await expectLater(strategy.cancel(), completes);
      });
    });

    group('one-shot contract', () {
      test('after cancel, a subsequent run on a new future does not resurrect '
          'the strategy into an active state', () async {
        // Arrange
        final strategy = ACOperationCancelStrategy();
        final first = Completer<int>();
        final firstRun = strategy.run<int>(first.future);
        await strategy.cancel();
        await firstRun;

        // Act
        // Attempting a second run on the same instance is out of contract
        // (per data-model §7: run is called at most once per lifecycle).
        // We only assert that the strategy does NOT falsely report itself
        // as holding a fresh active operation before the second call, and
        // that repeated cancel() remains safe.
        await expectLater(strategy.cancel(), completes);

        // Assert
        expect(strategy.isActive, isFalse);
      });
    });

    group('subtype contract', () {
      test('is an ACCancelStrategy', () {
        // Arrange
        final strategy = ACOperationCancelStrategy();

        // Act & Assert
        expect(strategy, isA<ACCancelStrategy>());
      });
    });
  });
}
