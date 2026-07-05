// ignore_for_file: cascade_invocations, unused_element_parameter, prefer_const_constructors
import 'dart:async';

import 'package:appcraft_list_loading_flutter/src/ac_loading_dispatcher.dart';
import 'package:appcraft_list_loading_flutter/src/ac_page.dart';
import 'package:appcraft_list_loading_flutter/src/ac_page_dispatcher.dart';
import 'package:appcraft_list_loading_flutter/src/ac_params.dart';
import 'package:appcraft_list_loading_flutter/src/ac_search_strategy.dart';
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

/// A minimal third-party subclass of [ACLoadingDispatcher] accumulating a
/// `List<int>`. It reuses the inherited loading engine verbatim — the loading
/// flags / [loadingListenable] under test are entirely the base class's
/// responsibility.
final class _IntAccumulatorDispatcher
    extends ACLoadingDispatcher<_TestParams, List<int>> {
  _IntAccumulatorDispatcher({super.searchStrategy});

  final List<int> _items = <int>[];
  bool _hasMore = true;

  /// Number of times [onLoadSuccess] fired.
  int successCalls = 0;

  /// Number of times [onLoadRejected] fired.
  int rejectedCalls = 0;

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
    successCalls++;
    if (replace) {
      _items.clear();
    }
    _items.addAll(result);
    _hasMore = result.isNotEmpty;
    notifyListeners();
  }

  @override
  void onLoadRejected() {
    rejectedCalls++;
    final wasNotEmpty = _items.isNotEmpty;
    _items.clear();
    _hasMore = false;
    if (wasNotEmpty) {
      notifyListeners();
    }
  }
}

/// Builds a dispatcher whose search strategy launches immediately (no
/// debounce, no minLength gate) so tests control timing via the loader alone.
_IntAccumulatorDispatcher _buildDispatcher({ACSearchStrategy? searchStrategy}) =>
    _IntAccumulatorDispatcher(
      searchStrategy: searchStrategy ??
          ACDebouncedSearchStrategy(
            debounce: Duration.zero,
            minLength: 0,
          ),
    );

/// Records the sequence of [ACLoadingDispatcher.loadingListenable] values,
/// captured at each notification.
List<bool> _recordLoading(ACLoadingDispatcher<dynamic, dynamic> dispatcher) {
  final recorded = <bool>[];
  dispatcher.loadingListenable.addListener(() {
    recorded.add(dispatcher.loadingListenable.value);
  });
  return recorded;
}

/// Page-model DTO for the [ACPageDispatcher] smoke scenario.
final class _FakePage<T> with ACPage<T> {
  const _FakePage({required this.items, required this.hasMore});

  @override
  final List<T> items;
  @override
  final bool hasMore;
}

void main() {
  group('ACLoadingDispatcher — loading state / loadingListenable (008)', () {
    // ---- Scenario 1 -------------------------------------------------------
    test('freshDispatcher_allFlagsAndListenableFalse', () {
      // Arrange
      final dispatcher = _buildDispatcher();

      // Act & Assert
      expect(dispatcher.isReloading, isFalse);
      expect(dispatcher.isLoadingMore, isFalse);
      expect(dispatcher.isLoading, isFalse);
      expect(dispatcher.loadingListenable.value, isFalse);

      dispatcher.dispose();
    });

    // ---- Scenario 2 -------------------------------------------------------
    test('reload_togglesListenableTrueSyncThenFalse_reloadingDuringLoad',
        () async {
      // Arrange — a gated loader lets us observe the in-flight state.
      final dispatcher = _buildDispatcher();
      final recorded = _recordLoading(dispatcher);
      final gate = Completer<List<int>>();
      Future<List<int>> slowLoad(_TestParams _) => gate.future;

      // Act — the loading flag flips synchronously on the call itself.
      final future = dispatcher.reload(
        params: const _TestParams(),
        load: slowLoad,
      );

      // Assert — synchronous true + in-flight phase flags.
      expect(recorded, equals(<bool>[true]),
          reason: 'listenable fires true synchronously at reload start');
      expect(dispatcher.loadingListenable.value, isTrue);
      expect(dispatcher.isReloading, isTrue);
      expect(dispatcher.isLoadingMore, isFalse);
      expect(dispatcher.isLoading, isTrue);

      // Act — complete the load.
      gate.complete(<int>[1, 2]);
      await future;

      // Assert — reset to false on completion.
      expect(recorded, equals(<bool>[true, false]));
      expect(dispatcher.loadingListenable.value, isFalse);
      expect(dispatcher.isReloading, isFalse);
      expect(dispatcher.isLoadingMore, isFalse);
      expect(dispatcher.isLoading, isFalse);

      dispatcher.dispose();
    });

    // ---- Scenario 3 -------------------------------------------------------
    test('loadMore_hasMoreTrue_togglesListenable_loadingMoreDuringLoad',
        () async {
      // Arrange — seed items so hasMore=true, then observe a gated loadMore.
      final dispatcher = _buildDispatcher();
      final seedLoader = FakeLoader<List<int>>();
      seedLoader.enqueueValue(<int>[1, 2]);
      await dispatcher.reload(
        params: const _TestParams(),
        load: seedLoader.call,
      );
      expect(dispatcher.hasMore, isTrue);

      final recorded = _recordLoading(dispatcher);
      final gate = Completer<List<int>>();
      Future<List<int>> slowLoad(_TestParams _) => gate.future;

      // Act — start loadMore; the flag flips synchronously.
      final future = dispatcher.loadMore(
        params: const _TestParams(),
        load: slowLoad,
      );

      // Assert — in-flight loadMore phase.
      expect(recorded, equals(<bool>[true]));
      expect(dispatcher.isLoadingMore, isTrue);
      expect(dispatcher.isReloading, isFalse);
      expect(dispatcher.isLoading, isTrue);

      // Act — complete.
      gate.complete(<int>[3, 4]);
      await future;

      // Assert
      expect(recorded, equals(<bool>[true, false]));
      expect(dispatcher.isLoadingMore, isFalse);
      expect(dispatcher.isLoading, isFalse);

      dispatcher.dispose();
    });

    // ---- Scenario 4 -------------------------------------------------------
    test('loadMore_hasMoreFalse_noListenableEvents_flagsStayFalse', () async {
      // Arrange — an empty result drives hasMore=false.
      final dispatcher = _buildDispatcher();
      final seedLoader = FakeLoader<List<int>>();
      seedLoader.enqueueValue(<int>[]);
      await dispatcher.reload(
        params: const _TestParams(),
        load: seedLoader.call,
      );
      expect(dispatcher.hasMore, isFalse);

      final recorded = _recordLoading(dispatcher);
      final loader = FakeLoader<List<int>>();
      loader.enqueueValue(<int>[9]);

      // Act
      await dispatcher.loadMore(
        params: const _TestParams(),
        load: loader.call,
      );

      // Assert — no-op: deduped listenable emits nothing, flags untouched.
      expect(recorded, isEmpty,
          reason: 'a no-op loadMore must not toggle loadingListenable');
      expect(loader.callCount, equals(0));
      expect(dispatcher.isLoading, isFalse);
      expect(dispatcher.isReloading, isFalse);
      expect(dispatcher.isLoadingMore, isFalse);

      dispatcher.dispose();
    });

    // ---- Scenario 5 -------------------------------------------------------
    test('reloadDuringLoadMore_preemptsWithoutFalseTransition', () async {
      // Arrange — seed hasMore=true.
      final dispatcher = _buildDispatcher();
      final seedLoader = FakeLoader<List<int>>();
      seedLoader.enqueueValue(<int>[1, 2]);
      await dispatcher.reload(
        params: const _TestParams(),
        load: seedLoader.call,
      );

      final recorded = _recordLoading(dispatcher);
      final loadMoreGate = Completer<List<int>>();
      Future<List<int>> slowLoadMore(_TestParams _) => loadMoreGate.future;
      final reloadLoader = FakeLoader<List<int>>();
      reloadLoader.enqueueValue(<int>[5, 6]);

      // Act — start an in-flight loadMore, then preempt it with a reload.
      final loadMoreFuture = dispatcher.loadMore(
        params: const _TestParams(),
        load: slowLoadMore,
      );
      expect(dispatcher.isLoadingMore, isTrue);

      final reloadFuture = dispatcher.reload(
        params: const _TestParams(),
        load: reloadLoader.call,
      );

      // Assert — reload took over synchronously, no false in between.
      final duringPreemption = List<bool>.of(recorded);
      expect(dispatcher.isReloading, isTrue);
      expect(dispatcher.isLoadingMore, isFalse);
      expect(dispatcher.isLoading, isTrue);
      expect(duringPreemption, equals(<bool>[true]),
          reason: 'isLoading must not dip through false on preemption');

      // Act — resolve both; the superseded loadMore result is dropped.
      loadMoreGate.complete(<int>[7, 8]);
      await Future.wait(<Future<void>>[loadMoreFuture, reloadFuture]);

      // Assert
      expect(recorded, equals(<bool>[true, false]));
      expect(dispatcher.items, equals(<int>[5, 6]));
      expect(dispatcher.isLoading, isFalse);

      dispatcher.dispose();
    });

    // ---- Scenario 6 -------------------------------------------------------
    test('reload_minLengthRejection_listenableReflectsTrueThenFalse',
        () async {
      // Arrange — a real minLength gate; a short query is rejected.
      final dispatcher = _buildDispatcher(
        searchStrategy: ACDebouncedSearchStrategy(minLength: 3),
      );
      final recorded = _recordLoading(dispatcher);
      final loader = FakeLoader<List<int>>();
      loader.enqueueValue(<int>[1]);

      // Act — query 'ab' (length 2) < minLength.
      await dispatcher.reload(
        params: const _TestParams(query: 'ab'),
        load: loader.call,
      );

      // Assert — the loader never ran, yet loading toggled true->false.
      expect(loader.callCount, equals(0));
      expect(dispatcher.rejectedCalls, equals(1));
      expect(recorded, equals(<bool>[true, false]));
      expect(dispatcher.loadingListenable.value, isFalse);
      expect(dispatcher.isLoading, isFalse);

      dispatcher.dispose();
    });

    // ---- Scenario 7 -------------------------------------------------------
    test('reload_loaderThrows_propagatesAndResetsListenable', () async {
      // Arrange
      final dispatcher = _buildDispatcher();
      final recorded = _recordLoading(dispatcher);
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

      // Assert — loading is reset via try/finally despite the throw.
      expect(dispatcher.isLoading, isFalse);
      expect(dispatcher.loadingListenable.value, isFalse);
      expect(recorded, equals(<bool>[true, false]));

      dispatcher.dispose();
    });

    // ---- Scenario 8 -------------------------------------------------------
    test('loadingChange_doesNotNotifyChangeNotifier_onlyItemsDo', () async {
      // Arrange — count ChangeNotifier notifications separately from the
      // reactive loading channel.
      final dispatcher = _buildDispatcher();
      var notifyCount = 0;
      dispatcher.addListener(() => notifyCount++);
      final recorded = _recordLoading(dispatcher);
      final gate = Completer<List<int>>();
      Future<List<int>> slowLoad(_TestParams _) => gate.future;

      // Act — start a reload; loading flips true but items are unchanged.
      final future = dispatcher.reload(
        params: const _TestParams(),
        load: slowLoad,
      );

      // Assert — the loading start notified loadingListenable, not the
      // ChangeNotifier.
      expect(recorded, equals(<bool>[true]));
      expect(notifyCount, equals(0),
          reason: 'an isLoading change must not notify ChangeNotifier');

      // Act — complete: now items change once.
      gate.complete(<int>[1, 2]);
      await future;

      // Assert — exactly one notify (from items), two loading transitions.
      expect(recorded, equals(<bool>[true, false]));
      expect(notifyCount, equals(1),
          reason: 'only the items change notifies ChangeNotifier');

      dispatcher.dispose();
    });

    // ---- Scenario 9 -------------------------------------------------------
    test('dispose_isIdempotent', () {
      // Arrange
      final dispatcher = _buildDispatcher();

      // Act & Assert — a repeated dispose is a safe no-op.
      dispatcher.dispose();
      expect(dispatcher.dispose, returnsNormally);
    });

    // ---- Scenario 10 ------------------------------------------------------
    test('acPageDispatcher_inheritsLoadingListenableAndPhaseFlags', () async {
      // Arrange — the real page dispatcher, freshly built.
      final dispatcher = ACPageDispatcher<_TestParams, _FakePage<int>, int>(
        searchStrategy: ACDebouncedSearchStrategy(
          debounce: Duration.zero,
          minLength: 0,
        ),
      );

      // Assert — fresh state inherited from the base engine.
      expect(dispatcher.isReloading, isFalse);
      expect(dispatcher.isLoadingMore, isFalse);
      expect(dispatcher.loadingListenable.value, isFalse);

      final recorded = _recordLoading(dispatcher);
      final gate = Completer<_FakePage<int>>();
      Future<_FakePage<int>> slowLoad(_TestParams _) => gate.future;

      // Act — reload flips reloading synchronously.
      final future = dispatcher.reload(
        params: const _TestParams(),
        load: slowLoad,
      );
      expect(dispatcher.isReloading, isTrue);
      expect(dispatcher.isLoadingMore, isFalse);
      expect(recorded, equals(<bool>[true]));

      // Act — complete.
      gate.complete(const _FakePage<int>(items: <int>[1, 2], hasMore: false));
      await future;

      // Assert
      expect(recorded, equals(<bool>[true, false]));
      expect(dispatcher.isReloading, isFalse);
      expect(dispatcher.loadingListenable.value, isFalse);
      expect(dispatcher.items, equals(<int>[1, 2]));

      dispatcher.dispose();
    });
  });
}
