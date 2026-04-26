// ignore_for_file: cascade_invocations, prefer_const_constructors
import 'dart:async';

import 'package:appcraft_list_loading_flutter/appcraft_list_loading_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_loader.dart';

/// Offset-based params — used by the `ACDefaultDispatcher`.
final class _TestParams
    with ACParamsMixin, ACOffsetParamsMixin {
  const _TestParams({this.offset, this.limit, this.query});

  @override
  final int? offset;
  @override
  final int? limit;
  @override
  final String? query;
}

/// DTO that mixes [ACResult] — used by
/// `ACCustomDispatcher` based tests.
final class _TestPage<T> with ACResult<T> {
  const _TestPage(this.items, {this.hasMore = true});

  @override
  final List<T> items;
  @override
  final bool hasMore;
}

void main() {
  group('ACDispatcher.lastResult — contract (US-LR)', () {
    test('AC-LR-1: lastResult returns null before first reload', () {
      // Arrange
      final dispatcher = ACDefaultDispatcher<_TestParams, int>();

      // Act & Assert
      expect(dispatcher.lastResult, isNull);

      dispatcher.dispose();
    });

    test('AC-LR-2: lastResult updates after successful reload', () async {
      // Arrange
      final dispatcher = ACCustomDispatcher<_TestParams,
          _TestPage<int>, int>();
      final loader = FakeLoader<_TestPage<int>>();
      final page = _TestPage<int>(<int>[1, 2, 3]);
      loader.enqueueValue(page);

      // Act
      await dispatcher.reload(
        params: const _TestParams(limit: 20),
        load: loader.call,
      );

      // Assert
      expect(dispatcher.lastResult, isA<_TestPage<int>>());
      expect(dispatcher.lastResult, same(page));
      expect(dispatcher.lastResult!.items, equals(<int>[1, 2, 3]));
      expect(dispatcher.lastResult!.hasMore, isTrue);

      dispatcher.dispose();
    });

    test(
        'AC-LR-3: lastResult updates after successful loadMore — returns '
        'latest result', () async {
      // Arrange — first reload seeds, then loadMore returns the latest page.
      final dispatcher = ACCustomDispatcher<_TestParams,
          _TestPage<int>, int>();
      final loader = FakeLoader<_TestPage<int>>();
      final firstPage = _TestPage<int>(<int>[1, 2]);
      final secondPage = _TestPage<int>(<int>[3, 4], hasMore: false);
      loader.enqueueValue(firstPage);
      loader.enqueueValue(secondPage);
      await dispatcher.reload(
        params: const _TestParams(limit: 2),
        load: loader.call,
      );
      expect(dispatcher.lastResult, same(firstPage));

      // Act
      await dispatcher.loadMore(
        params: const _TestParams(limit: 2, offset: 2),
        load: loader.call,
      );

      // Assert — lastResult must now point to the most recent successful load.
      expect(dispatcher.lastResult, same(secondPage));
      expect(dispatcher.lastResult!.items, equals(<int>[3, 4]));
      expect(dispatcher.lastResult!.hasMore, isFalse);

      dispatcher.dispose();
    });

    test('AC-LR-4: lastResult preserves on minLength rejection', () async {
      // Arrange — minLength=3 strategy; first reload without a query succeeds.
      final dispatcher = ACDefaultDispatcher<_TestParams, int>(
        searchStrategy: ACDebouncedSearchStrategy(
          debounce: Duration.zero,
          minLength: 3,
        ),
      );
      final loader = FakeLoader<List<int>>();
      final firstPage = <int>[1, 2];
      loader.enqueueValue(firstPage);
      await dispatcher.reload(
        params: const _TestParams(limit: 20),
        load: loader.call,
      );
      expect(dispatcher.lastResult, same(firstPage));
      final callsBefore = loader.callCount;

      // Act — short query (length=2 < minLength=3) → rejection.
      await dispatcher.reload(
        params: const _TestParams(query: 'ab'),
        load: loader.call,
      );

      // Assert — loader was not invoked again, lastResult unchanged.
      expect(loader.callCount, equals(callsBefore),
          reason: 'minLength rejection must not invoke the loader');
      expect(dispatcher.lastResult, same(firstPage));

      dispatcher.dispose();
    });

    test('AC-LR-5: lastResult preserves on loader exception', () async {
      // Arrange — first reload succeeds, second one throws.
      final dispatcher = ACCustomDispatcher<_TestParams,
          _TestPage<int>, int>();
      final loader = FakeLoader<_TestPage<int>>();
      final firstPage = _TestPage<int>(<int>[1, 2, 3]);
      loader.enqueueValue(firstPage);
      await dispatcher.reload(
        params: const _TestParams(limit: 20),
        load: loader.call,
      );
      expect(dispatcher.lastResult, same(firstPage));
      final failure = Exception('boom');
      loader.enqueueError(failure);

      // Act & Assert — error propagates, but lastResult stays the same.
      await expectLater(
        dispatcher.reload(
          params: const _TestParams(limit: 20),
          load: loader.call,
        ),
        throwsA(same(failure)),
      );
      expect(dispatcher.lastResult, same(firstPage),
          reason: 'failed reload must not overwrite previous lastResult');

      dispatcher.dispose();
    });

    test('AC-LR-6: lastResult preserves on cancel before completion',
        () async {
      // Arrange — successful reload seeds lastResult.
      final dispatcher = ACCustomDispatcher<_TestParams,
          _TestPage<int>, int>();
      final seedLoader = FakeLoader<_TestPage<int>>();
      final firstPage = _TestPage<int>(<int>[1, 2]);
      seedLoader.enqueueValue(firstPage);
      await dispatcher.reload(
        params: const _TestParams(limit: 2),
        load: seedLoader.call,
      );
      expect(dispatcher.lastResult, same(firstPage));

      // Start a load that will never complete on its own — gated future.
      final gate = Completer<_TestPage<int>>();
      Future<_TestPage<int>> gatedLoad(_TestParams _) => gate.future;
      final loadMoreFuture = dispatcher.loadMore(
        params: const _TestParams(limit: 2, offset: 2),
        load: gatedLoad,
      );
      expect(dispatcher.isLoading, isTrue);

      // Act — cancel before the gated loader resolves.
      await dispatcher.cancel();
      // Resolve the gated future after cancel — the result must be ignored.
      gate.complete(_TestPage<int>(<int>[9, 9, 9], hasMore: false));
      try {
        await loadMoreFuture;
      } on Object catch (_) {
        // Cancellation may or may not propagate — both are acceptable.
      }

      // Assert
      expect(dispatcher.lastResult, same(firstPage),
          reason: 'cancel must not overwrite lastResult with the late result');
      expect(dispatcher.isLoading, isFalse);

      dispatcher.dispose();
    });

    test('AC-LR-7: lastResult resets to null on dispose', () async {
      // Arrange
      final dispatcher = ACCustomDispatcher<_TestParams,
          _TestPage<int>, int>();
      final loader = FakeLoader<_TestPage<int>>();
      final firstPage = _TestPage<int>(<int>[1, 2, 3]);
      loader.enqueueValue(firstPage);
      await dispatcher.reload(
        params: const _TestParams(limit: 20),
        load: loader.call,
      );
      expect(dispatcher.lastResult, same(firstPage));

      // Act
      dispatcher.dispose();

      // Assert
      expect(dispatcher.lastResult, isNull,
          reason: 'dispose must clear lastResult');
    });
  });
}
