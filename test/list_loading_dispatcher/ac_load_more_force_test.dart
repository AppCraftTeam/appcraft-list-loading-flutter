// ignore_for_file: cascade_invocations, unused_element_parameter, prefer_const_constructors
import 'dart:async';

import 'package:appcraft_list_loading_flutter/src/ac_list_dispatcher.dart';
import 'package:appcraft_list_loading_flutter/src/ac_page.dart';
import 'package:appcraft_list_loading_flutter/src/ac_page_dispatcher.dart';
import 'package:appcraft_list_loading_flutter/src/ac_params.dart';
import 'package:appcraft_list_loading_flutter/src/ac_search_debouncer.dart';
import 'package:appcraft_list_loading_flutter/src/ac_search_strategy.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_loader.dart';

/// Offset-based params for [ACListDispatcher]: the loader returns a bare
/// `List<int>` and `hasMore` is recomputed from `params.limit`.
final class _ListParams with ACParamsMixin, ACOffsetParamsMixin {
  const _ListParams({this.limit, this.offset, this.query});

  @override
  final int? limit;
  @override
  final int? offset;
  @override
  final String? query;
}

/// Page-model params for [ACPageDispatcher]: `hasMore` comes from the page.
final class _PageParams with ACParamsMixin {
  const _PageParams({this.limit, this.query});

  @override
  final int? limit;
  @override
  final String? query;
}

/// Minimal page-model DTO carrying its own `hasMore` flag.
final class _FakePage<T> with ACPage<T> {
  const _FakePage({required this.items, required this.hasMore});

  @override
  final List<T> items;
  @override
  final bool hasMore;
}

/// A search strategy that launches immediately (no debounce, no minLength
/// gate) so tests control timing purely via the loader.
ACSearchStrategy _immediateStrategy() => ACSearchDebouncer(
      debounce: Duration.zero,
      minLength: 0,
    );

ACListDispatcher<_ListParams, int> _buildListDispatcher() =>
    ACListDispatcher<_ListParams, int>(searchStrategy: _immediateStrategy());

ACPageDispatcher<_PageParams, _FakePage<int>, int> _buildPageDispatcher() =>
    ACPageDispatcher<_PageParams, _FakePage<int>, int>(
      searchStrategy: _immediateStrategy(),
    );

void main() {
  group('ACLoadingDispatcher.loadMore(force:) — ACListDispatcher (009)', () {
    // ---- Scenario 1: F1 -------------------------------------------------
    test('hasMoreFalse_forceTrue_loadsAppendsRecomputesAndNotifiesOnce',
        () async {
      // Arrange — an empty first page drives hasMore=false.
      final dispatcher = _buildListDispatcher();
      final seed = FakeLoader<List<int>>();
      seed.enqueueValue(<int>[]);
      await dispatcher.reload(
        params: const _ListParams(limit: 2),
        load: seed.call,
      );
      expect(dispatcher.hasMore, isFalse);
      expect(dispatcher.items, isEmpty);

      var notifyCount = 0;
      dispatcher.addListener(() => notifyCount++);
      final loader = FakeLoader<List<int>>();
      loader.enqueueValue(<int>[1, 2]);

      // Act
      await dispatcher.loadMore(
        params: const _ListParams(limit: 2),
        load: loader.call,
        force: true,
      );

      // Assert — loader ran, items appended, hasMore recomputed, one notify.
      expect(loader.callCount, equals(1));
      expect(dispatcher.items, equals(<int>[1, 2]));
      expect(dispatcher.hasMore, isTrue,
          reason: 'result.length (2) >= limit (2) recomputes hasMore=true');
      expect(notifyCount, equals(1));

      dispatcher.dispose();
    });

    // ---- Scenario 2: F4 -------------------------------------------------
    test('hasMoreFalse_noForce_isNoOp', () async {
      // Arrange
      final dispatcher = _buildListDispatcher();
      final seed = FakeLoader<List<int>>();
      seed.enqueueValue(<int>[]);
      await dispatcher.reload(
        params: const _ListParams(limit: 2),
        load: seed.call,
      );
      expect(dispatcher.hasMore, isFalse);

      var notifyCount = 0;
      dispatcher.addListener(() => notifyCount++);
      final loader = FakeLoader<List<int>>();
      loader.enqueueValue(<int>[9]);

      // Act
      await dispatcher.loadMore(
        params: const _ListParams(limit: 2),
        load: loader.call,
      );

      // Assert — no-op: loader untouched, state unchanged.
      expect(loader.callCount, equals(0));
      expect(dispatcher.items, isEmpty);
      expect(notifyCount, equals(0));

      dispatcher.dispose();
    });

    // ---- Scenario 3: F6 -------------------------------------------------
    test('hasMoreTrue_forceTrue_behavesLikePlainLoadMore', () async {
      // Arrange — a full first page keeps hasMore=true.
      final dispatcher = _buildListDispatcher();
      final seed = FakeLoader<List<int>>();
      seed.enqueueValue(<int>[1, 2]);
      await dispatcher.reload(
        params: const _ListParams(limit: 2),
        load: seed.call,
      );
      expect(dispatcher.hasMore, isTrue);

      final loader = FakeLoader<List<int>>();
      loader.enqueueValue(<int>[3, 4]);

      // Act
      await dispatcher.loadMore(
        params: const _ListParams(limit: 2),
        load: loader.call,
        force: true,
      );

      // Assert — appended, hasMore recomputed as usual.
      expect(loader.callCount, equals(1));
      expect(dispatcher.items, equals(<int>[1, 2, 3, 4]));
      expect(dispatcher.hasMore, isTrue);

      dispatcher.dispose();
    });

    // ---- Scenario 4: F5 (one-shot) --------------------------------------
    test('forceLoadReturningHasMoreFalse_thenPlainLoadMore_isNoOp', () async {
      // Arrange — reach hasMore=false, then force-load a short page that
      // recomputes hasMore=false again (result shorter than limit).
      final dispatcher = _buildListDispatcher();
      final seed = FakeLoader<List<int>>();
      seed.enqueueValue(<int>[]);
      await dispatcher.reload(
        params: const _ListParams(limit: 2),
        load: seed.call,
      );
      expect(dispatcher.hasMore, isFalse);

      final forceLoader = FakeLoader<List<int>>();
      forceLoader.enqueueValue(<int>[1]); // len 1 < limit 2 -> hasMore=false
      await dispatcher.loadMore(
        params: const _ListParams(limit: 2),
        load: forceLoader.call,
        force: true,
      );
      expect(dispatcher.items, equals(<int>[1]));
      expect(dispatcher.hasMore, isFalse,
          reason: 'force is one-shot; hasMore recomputed to false');

      final plainLoader = FakeLoader<List<int>>();
      plainLoader.enqueueValue(<int>[2]);

      // Act — plain loadMore must be a no-op again.
      await dispatcher.loadMore(
        params: const _ListParams(limit: 2),
        load: plainLoader.call,
      );

      // Assert
      expect(plainLoader.callCount, equals(0));
      expect(dispatcher.items, equals(<int>[1]));

      dispatcher.dispose();
    });

    // ---- Scenario 5: F2 -------------------------------------------------
    test('isLoadingTrue_forceTrue_isNoOp', () async {
      // Arrange — a gated reload keeps isLoading=true.
      final dispatcher = _buildListDispatcher();
      final gate = Completer<List<int>>();
      Future<List<int>> slowLoad(_ListParams _) => gate.future;
      final reloadFuture = dispatcher.reload(
        params: const _ListParams(limit: 2),
        load: slowLoad,
      );
      expect(dispatcher.isLoading, isTrue);

      final loader = FakeLoader<List<int>>();
      loader.enqueueValue(<int>[9]);

      // Act — force does not bypass the isLoading guard.
      await dispatcher.loadMore(
        params: const _ListParams(limit: 2),
        load: loader.call,
        force: true,
      );

      // Assert — no-op while a load is in flight.
      expect(loader.callCount, equals(0));

      // Cleanup — resolve the gated reload.
      gate.complete(<int>[1, 2]);
      await reloadFuture;

      dispatcher.dispose();
    });

    // ---- Scenario 6: F3 -------------------------------------------------
    test('afterDispose_forceTrue_isNoOp', () async {
      // Arrange
      final dispatcher = _buildListDispatcher();
      final loader = FakeLoader<List<int>>();
      loader.enqueueValue(<int>[1]);
      dispatcher.dispose();

      // Act — force does not bypass the disposed guard.
      await dispatcher.loadMore(
        params: const _ListParams(limit: 2),
        load: loader.call,
        force: true,
      );

      // Assert — loader never ran.
      expect(loader.callCount, equals(0));
    });

    // ---- Scenario 7: F6 (phase flags) -----------------------------------
    test('duringForceLoad_isLoadingMoreTrue_isReloadingFalse', () async {
      // Arrange — hasMore=false, then a gated force loadMore.
      final dispatcher = _buildListDispatcher();
      final seed = FakeLoader<List<int>>();
      seed.enqueueValue(<int>[]);
      await dispatcher.reload(
        params: const _ListParams(limit: 2),
        load: seed.call,
      );
      expect(dispatcher.hasMore, isFalse);

      final gate = Completer<List<int>>();
      Future<List<int>> slowLoad(_ListParams _) => gate.future;

      // Act — start a forced loadMore; flags flip synchronously.
      final future = dispatcher.loadMore(
        params: const _ListParams(limit: 2),
        load: slowLoad,
        force: true,
      );

      // Assert — the in-flight phase is loadMore, not reload.
      expect(dispatcher.isLoadingMore, isTrue);
      expect(dispatcher.isReloading, isFalse);
      expect(dispatcher.isLoading, isTrue);

      // Act — complete and settle.
      gate.complete(<int>[1]);
      await future;

      // Assert — flags reset afterwards.
      expect(dispatcher.isLoadingMore, isFalse);
      expect(dispatcher.isLoading, isFalse);

      dispatcher.dispose();
    });
  });

  group('ACLoadingDispatcher.loadMore(force:) — smoke on both (009)', () {
    // ---- Scenario 8a ----------------------------------------------------
    test('acListDispatcher_forceTrue_isAvailableAndWorks', () async {
      // Arrange
      final dispatcher = _buildListDispatcher();
      dispatcher.hasMore = false;
      final loader = FakeLoader<List<int>>();
      loader.enqueueValue(<int>[7, 8]);

      // Act
      await dispatcher.loadMore(
        params: const _ListParams(limit: 2),
        load: loader.call,
        force: true,
      );

      // Assert
      expect(loader.callCount, equals(1));
      expect(dispatcher.items, equals(<int>[7, 8]));

      dispatcher.dispose();
    });

    // ---- Scenario 8b ----------------------------------------------------
    test('acPageDispatcher_forceTrue_isAvailableAndWorks', () async {
      // Arrange — a page with hasMore=false blocks a plain loadMore.
      final dispatcher = _buildPageDispatcher();
      final seed = FakeLoader<_FakePage<int>>();
      seed.enqueueValue(const _FakePage<int>(items: <int>[1, 2], hasMore: false));
      await dispatcher.reload(
        params: const _PageParams(),
        load: seed.call,
      );
      expect(dispatcher.hasMore, isFalse);

      final loader = FakeLoader<_FakePage<int>>();
      loader.enqueueValue(const _FakePage<int>(items: <int>[3], hasMore: true));

      // Act — force bypasses the hasMore guard on the inherited method.
      await dispatcher.loadMore(
        params: const _PageParams(),
        load: loader.call,
        force: true,
      );

      // Assert — appended and hasMore recomputed from the page model.
      expect(loader.callCount, equals(1));
      expect(dispatcher.items, equals(<int>[1, 2, 3]));
      expect(dispatcher.hasMore, isTrue);

      dispatcher.dispose();
    });
  });
}
