// ignore_for_file: cascade_invocations, unused_element_parameter, prefer_const_constructors
import 'dart:async';

import 'package:appcraft_list_loading_flutter/appcraft_list_loading_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_loader.dart';

/// Minimal params — the base engine only reads [query] for the search
/// strategy; [limit] is carried through to the loader untouched.
final class _TestParams with ACParamsMixin {
  const _TestParams({this.limit, this.query});

  @override
  final int? limit;
  @override
  final String? query;
}

/// Offset-based params for the real [ACListDispatcher] smoke scenario.
final class _ListParams with ACParamsMixin, ACOffsetParamsMixin {
  const _ListParams({this.limit, this.offset, this.query});

  @override
  final int? limit;
  @override
  final int? offset;
  @override
  final String? query;
}

/// Page-model DTO for the [ACPageDispatcher] smoke scenario.
final class _FakePage<T> with ACPage<T> {
  const _FakePage({required this.items, required this.hasMore});

  @override
  final List<T> items;
  @override
  final bool hasMore;
}

/// A minimal third-party subclass of [ACLoadingDispatcher] accumulating a
/// `List<int>`. The error-state / retry / lastOperation members under test are
/// entirely the base class's responsibility; this subclass only wires the
/// collection hooks.
final class _IntAccumulatorDispatcher
    extends ACLoadingDispatcher<_TestParams, List<int>> {
  _IntAccumulatorDispatcher({super.searchStrategy});

  final List<int> _items = <int>[];
  bool _hasMore = true;

  /// Unmodifiable view of the accumulated items.
  List<int> get items => List<int>.unmodifiable(_items);

  @override
  bool get hasMore => _hasMore;

  @override
  void onLoadSuccess(
    List<int> result,
    _TestParams params, {
    required bool replace,
  }) {
    if (replace) {
      _items.clear();
    }
    _items.addAll(result);
    _hasMore = result.isNotEmpty;
    notifyListeners();
  }

  @override
  void onLoadRejected() {
    final wasNotEmpty = _items.isNotEmpty;
    _items.clear();
    _hasMore = false;
    if (wasNotEmpty) {
      notifyListeners();
    }
  }
}

/// Builds a base-engine subclass whose search strategy launches immediately
/// (no debounce, no minLength gate) so tests control timing via the loader.
_IntAccumulatorDispatcher _buildDispatcher({ACSearchStrategy? searchStrategy}) =>
    _IntAccumulatorDispatcher(
      searchStrategy: searchStrategy ??
          ACSearchDebouncer(
            debounce: Duration.zero,
            minLength: 0,
          ),
    );

ACSearchStrategy _immediateStrategy() => ACSearchDebouncer(
      debounce: Duration.zero,
      minLength: 0,
    );

/// Records the sequence of [ACLoadingDispatcher.errorListenable] values,
/// captured at each notification.
List<Object?> _recordErrors(ACLoadingDispatcher<dynamic, dynamic> dispatcher) {
  final recorded = <Object?>[];
  dispatcher.errorListenable.addListener(() {
    recorded.add(dispatcher.errorListenable.value);
  });
  return recorded;
}

void main() {
  // =====================================================================
  // T005 — error-state (scenarios 1–4, 10, 11)
  // =====================================================================
  group('ACLoadingDispatcher — error state (010)', () {
    // ---- Scenario 1 -----------------------------------------------------
    test('freshDispatcher_lastErrorAndListenableNull', () {
      // Arrange
      final dispatcher = _buildDispatcher();

      // Act & Assert
      expect(dispatcher.lastError, isNull);
      expect(dispatcher.errorListenable.value, isNull);
      expect(dispatcher.lastOperation, isNull);

      dispatcher.dispose();
    });

    // ---- Scenario 2 (reload) --------------------------------------------
    test('reload_loaderThrows_capturesErrorAndNotifiesAndResetsLoading',
        () async {
      // Arrange
      final dispatcher = _buildDispatcher();
      final recorded = _recordErrors(dispatcher);
      final loader = FakeLoader<List<int>>();
      final failure = Exception('network down');
      loader.enqueueError(failure);

      // Act & Assert — the exception is propagated to the caller.
      await expectLater(
        dispatcher.reload(
          params: const _TestParams(),
          load: loader.call,
        ),
        throwsA(same(failure)),
      );

      // Assert — error captured, loading reset, subscriber notified.
      expect(dispatcher.isLoading, isFalse);
      expect(dispatcher.lastError, same(failure));
      expect(dispatcher.errorListenable.value, same(failure));
      expect(recorded, equals(<Object?>[failure]));

      dispatcher.dispose();
    });

    // ---- Scenario 2 (loadMore) ------------------------------------------
    test('loadMore_loaderThrows_capturesErrorAndNotifiesAndResetsLoading',
        () async {
      // Arrange — seed items so hasMore=true, then a failing loadMore.
      final dispatcher = _buildDispatcher();
      final seed = FakeLoader<List<int>>();
      seed.enqueueValue(<int>[1, 2]);
      await dispatcher.reload(
        params: const _TestParams(),
        load: seed.call,
      );
      expect(dispatcher.hasMore, isTrue);

      final recorded = _recordErrors(dispatcher);
      final loader = FakeLoader<List<int>>();
      final failure = Exception('page failed');
      loader.enqueueError(failure);

      // Act & Assert
      await expectLater(
        dispatcher.loadMore(
          params: const _TestParams(),
          load: loader.call,
        ),
        throwsA(same(failure)),
      );

      // Assert
      expect(dispatcher.isLoading, isFalse);
      expect(dispatcher.lastError, same(failure));
      expect(dispatcher.errorListenable.value, same(failure));
      expect(recorded, equals(<Object?>[failure]));

      dispatcher.dispose();
    });

    // ---- Scenario 3 -----------------------------------------------------
    test('errorThenSuccess_clearsLastErrorAndNotifies', () async {
      // Arrange — a failing reload records an error first.
      final dispatcher = _buildDispatcher();
      final failing = FakeLoader<List<int>>();
      final failure = Exception('boom');
      failing.enqueueError(failure);
      await expectLater(
        dispatcher.reload(
          params: const _TestParams(),
          load: failing.call,
        ),
        throwsA(same(failure)),
      );
      expect(dispatcher.lastError, same(failure));

      final recorded = _recordErrors(dispatcher);
      final success = FakeLoader<List<int>>();
      success.enqueueValue(<int>[1, 2]);

      // Act — a successful reload clears the error.
      await dispatcher.reload(
        params: const _TestParams(),
        load: success.call,
      );

      // Assert — error cleared to null and the subscriber was notified.
      expect(dispatcher.lastError, isNull);
      expect(dispatcher.errorListenable.value, isNull);
      expect(recorded, equals(<Object?>[null]));
      expect(dispatcher.items, equals(<int>[1, 2]));

      dispatcher.dispose();
    });

    // ---- Scenario 4 -----------------------------------------------------
    test('staleLoadError_isNotRecorded_afterPreemptionBySuccess', () async {
      // Arrange — load A is gated in-flight and will error; load B (a newer
      // reload) preempts it and succeeds.
      final dispatcher = _buildDispatcher();
      final recorded = _recordErrors(dispatcher);
      final gateA = Completer<List<int>>();
      Future<List<int>> slowLoadA(_TestParams _) => gateA.future;
      final loaderB = FakeLoader<List<int>>();
      loaderB.enqueueValue(<int>[5, 6]);

      // Act — start A, then preempt with B before A resolves.
      final futureA = dispatcher.reload(
        params: const _TestParams(),
        load: slowLoadA,
      );
      final futureB = dispatcher.reload(
        params: const _TestParams(),
        load: loaderB.call,
      );

      // The identical-guard: A's cancel strategy is no longer active.
      expect(dispatcher.isReloading, isTrue);

      // Act — resolve A with an error (now stale) and settle both.
      gateA.completeError(Exception('stale A'));
      await Future.wait(<Future<void>>[futureA, futureB]);

      // Assert — B's success stands; A's stale error was never recorded.
      expect(dispatcher.lastError, isNull);
      expect(dispatcher.errorListenable.value, isNull);
      expect(recorded, isEmpty,
          reason: 'a stale load error must not touch errorListenable');
      expect(dispatcher.items, equals(<int>[5, 6]));

      dispatcher.dispose();
    });

    // ---- Scenario 10 ----------------------------------------------------
    test('sameError_isDeduped_andDoesNotNotifyChangeNotifier', () async {
      // Arrange — count ChangeNotifier notifications separately from the
      // reactive error channel; the same error object is thrown twice.
      final dispatcher = _buildDispatcher();
      var notifyCount = 0;
      dispatcher.addListener(() => notifyCount++);
      final recorded = _recordErrors(dispatcher);
      final failure = Exception('repeat');
      final loader = FakeLoader<List<int>>();
      loader.enqueueError(failure);
      loader.enqueueError(failure);

      // Act — first failing reload records the error.
      await expectLater(
        dispatcher.reload(
          params: const _TestParams(),
          load: loader.call,
        ),
        throwsA(same(failure)),
      );

      // Act — a second failing reload assigns the same error object.
      await expectLater(
        dispatcher.reload(
          params: const _TestParams(),
          load: loader.call,
        ),
        throwsA(same(failure)),
      );

      // Assert — errorListenable fired exactly once (deduped); a lastError
      // change never notifies the ChangeNotifier (only items would).
      expect(recorded, equals(<Object?>[failure]),
          reason: 'the same error value must not re-emit');
      expect(notifyCount, equals(0),
          reason: 'changing lastError must not notify ChangeNotifier');

      dispatcher.dispose();
    });

    // ---- Scenario 11 ----------------------------------------------------
    test('dispose_isIdempotent_afterError', () async {
      // Arrange — record an error, then dispose twice.
      final dispatcher = _buildDispatcher();
      final loader = FakeLoader<List<int>>();
      final failure = Exception('boom');
      loader.enqueueError(failure);
      await expectLater(
        dispatcher.reload(
          params: const _TestParams(),
          load: loader.call,
        ),
        throwsA(same(failure)),
      );

      // Act & Assert — a repeated dispose is a safe no-op.
      dispatcher.dispose();
      expect(dispatcher.dispose, returnsNormally);
    });
  });

  // =====================================================================
  // T007 — retry (scenarios 5–8)
  // =====================================================================
  group('ACLoadingDispatcher — retry (010)', () {
    // ---- Scenario 5 -----------------------------------------------------
    test('retry_afterFailedReload_repeatsReloadWithSameParamsAndLoad',
        () async {
      // Arrange — a reload that fails first, then succeeds on the next call.
      final dispatcher = _buildDispatcher();
      final loader = FakeLoader<List<int>>();
      final failure = Exception('boom');
      loader.enqueueError(failure);
      loader.enqueueValue(<int>[1, 2]);
      const params = _TestParams(query: 'q');

      await expectLater(
        dispatcher.reload(params: params, load: loader.call),
        throwsA(same(failure)),
      );
      expect(dispatcher.lastError, same(failure));

      // Act — retry repeats the reload through the public entry point.
      await dispatcher.retry();

      // Assert — same params/load reused; success cleared the error.
      expect(loader.callCount, equals(2));
      expect(loader.calls, equals(<dynamic>[params, params]));
      expect(dispatcher.items, equals(<int>[1, 2]));
      expect(dispatcher.lastError, isNull);

      dispatcher.dispose();
    });

    // ---- Scenario 6 -----------------------------------------------------
    test('retry_afterFailedForcedLoadMore_repeatsWithForceAndSucceeds',
        () async {
      // Arrange — drive hasMore=false, then a forced loadMore that fails.
      final dispatcher = _buildDispatcher();
      final seed = FakeLoader<List<int>>();
      seed.enqueueValue(<int>[]);
      await dispatcher.reload(
        params: const _TestParams(),
        load: seed.call,
      );
      expect(dispatcher.hasMore, isFalse);

      final loader = FakeLoader<List<int>>();
      final failure = Exception('page boom');
      loader.enqueueError(failure);
      loader.enqueueValue(<int>[3, 4]);

      await expectLater(
        dispatcher.loadMore(
          params: const _TestParams(),
          load: loader.call,
          force: true,
        ),
        throwsA(same(failure)),
      );
      expect(dispatcher.lastError, same(failure));
      expect(dispatcher.lastOperation, isA<ACLoadMoreOperation<dynamic, dynamic>>());

      // Act — retry must reproduce force:true (not a no-op at hasMore=false).
      await dispatcher.retry();

      // Assert — the second call ran and appended; error cleared.
      expect(loader.callCount, equals(2));
      expect(dispatcher.items, equals(<int>[3, 4]));
      expect(dispatcher.lastError, isNull);

      dispatcher.dispose();
    });

    // ---- Scenario 7 -----------------------------------------------------
    test('retry_withoutOperations_isNoOp', () async {
      // Arrange
      final dispatcher = _buildDispatcher();

      // Act & Assert — nothing captured yet: a safe no-op.
      await dispatcher.retry();
      expect(dispatcher.lastOperation, isNull);
      expect(dispatcher.lastError, isNull);

      dispatcher.dispose();
    });

    test('retry_afterDispose_isNoOp', () async {
      // Arrange — capture a real reload, then dispose.
      final dispatcher = _buildDispatcher();
      final loader = FakeLoader<List<int>>();
      loader.enqueueValue(<int>[1]);
      await dispatcher.reload(
        params: const _TestParams(),
        load: loader.call,
      );
      dispatcher.dispose();

      // Act — retry after dispose must not re-run the loader.
      await dispatcher.retry();

      // Assert
      expect(loader.callCount, equals(1));
    });

    // ---- Scenario 8 -----------------------------------------------------
    test('noOpLoadMore_doesNotOverwriteLastOperation', () async {
      // Arrange — a reload leaves hasMore=false (empty result).
      final dispatcher = _buildDispatcher();
      final loader = FakeLoader<List<int>>();
      loader.enqueueValue(<int>[]);
      loader.enqueueValue(<int>[]);
      const params = _TestParams(query: 'seed');
      await dispatcher.reload(params: params, load: loader.call);
      expect(dispatcher.hasMore, isFalse);
      expect(dispatcher.lastOperation, isA<ACReloadOperation<dynamic, dynamic>>());

      final ignored = FakeLoader<List<int>>();
      ignored.enqueueValue(<int>[9]);

      // Act — a no-op loadMore (!hasMore, no force) must not overwrite.
      await dispatcher.loadMore(
        params: const _TestParams(query: 'other'),
        load: ignored.call,
      );

      // Assert — the previous real operation survives; retry repeats reload.
      expect(ignored.callCount, equals(0));
      expect(dispatcher.lastOperation, isA<ACReloadOperation<dynamic, dynamic>>());

      await dispatcher.retry();
      expect(loader.callCount, equals(2),
          reason: 'retry repeats the captured reload, not the no-op loadMore');
      expect(loader.calls.last, equals(params));

      dispatcher.dispose();
    });
  });

  // =====================================================================
  // T008 — lastOperation introspection (scenario 9)
  // =====================================================================
  group('ACLoadingDispatcher — lastOperation introspection (010)', () {
    test('beforeAnyOperation_lastOperationIsNull', () {
      // Arrange
      final dispatcher = _buildDispatcher();

      // Act & Assert
      expect(dispatcher.lastOperation, isNull);

      dispatcher.dispose();
    });

    test('afterReload_lastOperationIsReloadOperation', () async {
      // Arrange
      final dispatcher = _buildDispatcher();
      final loader = FakeLoader<List<int>>();
      loader.enqueueValue(<int>[1]);
      const params = _TestParams(query: 'x');

      // Act
      await dispatcher.reload(params: params, load: loader.call);

      // Assert — pattern match the sealed variant.
      final operation = dispatcher.lastOperation;
      expect(operation, isA<ACReloadOperation<_TestParams, List<int>>>());
      switch (operation) {
        case ACReloadOperation<_TestParams, List<int>>(:final params):
          expect(params.query, equals('x'));
        case ACLoadMoreOperation<_TestParams, List<int>>():
        case null:
          fail('expected a reload operation');
      }

      dispatcher.dispose();
    });

    test('afterForcedLoadMore_lastOperationIsLoadMoreWithForceAndParams',
        () async {
      // Arrange — hasMore=false so a forced loadMore is required.
      final dispatcher = _buildDispatcher();
      final seed = FakeLoader<List<int>>();
      seed.enqueueValue(<int>[]);
      await dispatcher.reload(
        params: const _TestParams(),
        load: seed.call,
      );
      expect(dispatcher.hasMore, isFalse);

      final loader = FakeLoader<List<int>>();
      loader.enqueueValue(<int>[3, 4]);
      const params = _TestParams(query: 'more', limit: 5);

      // Act
      await dispatcher.loadMore(
        params: params,
        load: loader.call,
        force: true,
      );

      // Assert — force flag and params are preserved.
      final operation = dispatcher.lastOperation;
      expect(operation, isA<ACLoadMoreOperation<_TestParams, List<int>>>());
      final loadMore = operation! as ACLoadMoreOperation<_TestParams, List<int>>;
      expect(loadMore.force, isTrue);
      expect(loadMore.params.query, equals('more'));
      expect(loadMore.params.limit, equals(5));

      dispatcher.dispose();
    });
  });

  // =====================================================================
  // T009 — parity smoke on both concrete dispatchers (scenario 12)
  // =====================================================================
  group('ACLoadingDispatcher — error/retry parity smoke (010)', () {
    test('acListDispatcher_errorRetryAndLastOperation_work', () async {
      // Arrange — a failing reload then a successful retry on the real
      // list dispatcher.
      final dispatcher =
          ACListDispatcher<_ListParams, int>(searchStrategy: _immediateStrategy());
      final loader = FakeLoader<List<int>>();
      final failure = Exception('list boom');
      loader.enqueueError(failure);
      loader.enqueueValue(<int>[1, 2]);

      // Act & Assert — error captured and propagated.
      await expectLater(
        dispatcher.reload(
          params: const _ListParams(limit: 2),
          load: loader.call,
        ),
        throwsA(same(failure)),
      );
      expect(dispatcher.lastError, same(failure));
      expect(dispatcher.errorListenable.value, same(failure));
      expect(
        dispatcher.lastOperation,
        isA<ACReloadOperation<_ListParams, List<int>>>(),
      );

      // Act — retry clears the error and applies the result.
      await dispatcher.retry();
      expect(dispatcher.lastError, isNull);
      expect(dispatcher.items, equals(<int>[1, 2]));

      dispatcher.dispose();
    });

    test('acPageDispatcher_errorRetryAndLastOperation_work', () async {
      // Arrange
      final dispatcher = ACPageDispatcher<_TestParams, _FakePage<int>, int>(
        searchStrategy: _immediateStrategy(),
      );
      final loader = FakeLoader<_FakePage<int>>();
      final failure = Exception('page boom');
      loader.enqueueError(failure);
      loader.enqueueValue(
        const _FakePage<int>(items: <int>[9], hasMore: false),
      );

      // Act & Assert
      await expectLater(
        dispatcher.reload(
          params: const _TestParams(),
          load: loader.call,
        ),
        throwsA(same(failure)),
      );
      expect(dispatcher.lastError, same(failure));
      expect(dispatcher.errorListenable.value, same(failure));
      expect(
        dispatcher.lastOperation,
        isA<ACReloadOperation<_TestParams, _FakePage<int>>>(),
      );

      // Act — retry
      await dispatcher.retry();
      expect(dispatcher.lastError, isNull);
      expect(dispatcher.items, equals(<int>[9]));

      dispatcher.dispose();
    });
  });
}
