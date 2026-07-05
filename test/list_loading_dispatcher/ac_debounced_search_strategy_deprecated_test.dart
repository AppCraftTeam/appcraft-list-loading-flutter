// Verifies the deprecated ACDebouncedSearchStrategy still works until it is
// removed in 1.0.0. Full behavioural coverage lives in
// ac_search_debouncer_test.dart against the replacement ACSearchDebouncer.
// ignore_for_file: deprecated_member_use_from_same_package
// ignore_for_file: prefer_const_constructors, cascade_invocations
import 'package:appcraft_list_loading_flutter/src/ac_search_strategy.dart';
import 'package:appcraft_list_loading_flutter/src/deprecated/ac_debounced_search_strategy.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ACDebouncedSearchStrategy (deprecated)', () {
    test('is still an ACSearchStrategy with the documented defaults', () {
      // Arrange & Act
      final strategy = ACDebouncedSearchStrategy();

      // Assert
      expect(strategy, isA<ACSearchStrategy>());
      expect(strategy.debounce, equals(const Duration(milliseconds: 300)));
      expect(strategy.minLength, equals(3));
    });

    test('schedule debounces a changed query and cancel stops it', () {
      FakeAsync().run((async) {
        // Arrange
        final strategy = ACDebouncedSearchStrategy(
          debounce: const Duration(milliseconds: 300),
        );

        // Act — a changed valid query is deferred through the debounce.
        var applied = false;
        strategy.schedule('john')!.then((_) => applied = true);
        async.elapse(const Duration(milliseconds: 300));
        async.flushMicrotasks();

        // Assert — the deferred load completed.
        expect(applied, isTrue);

        // Act — a fresh query cancelled before its timer fires never runs.
        var cancelled = false;
        strategy.schedule('jane')!.then((_) => cancelled = true);
        async.elapse(const Duration(milliseconds: 100));
        strategy.cancel();
        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();

        // Assert
        expect(cancelled, isFalse,
            reason: 'cancel() must stop the pending debounce timer');
      });
    });
  });
}
