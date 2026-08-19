// ignore_for_file: deprecated_member_use_from_same_package — this file
// covers the deprecated around-API, whose behaviour stays under test
// until it is removed in 2.0.0.
// ignore_for_file: cascade_invocations, unused_element_parameter, prefer_const_constructors
import 'dart:async';

import 'package:appcraft_list_loading_flutter/appcraft_list_loading_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_loader.dart';

/// Around-page model for `loadAround`: carries both directional flags at once.
final class _Around with ACAnchoredPage<int> {
  const _Around({
    required this.items,
    required this.hasMoreOlder,
    required this.hasMoreNewer,
  });

  @override
  final List<int> items;
  @override
  final bool hasMoreOlder;
  @override
  final bool hasMoreNewer;
}

/// Per-side page model. Here `hasMore` means «is there more on **this** side».
final class _Page with ACPage<int> {
  const _Page({required this.items, required this.hasMore});

  @override
  final List<int> items;
  @override
  final bool hasMore;
}

/// Minimal params — the anchored dispatcher only forwards them to the loader.
final class _Params with ACParamsMixin {
  const _Params({this.limit, this.query});

  @override
  final int? limit;
  @override
  final String? query;
}

ACAnchoredDispatcher<_Params, _Page, int> _build() =>
    ACAnchoredDispatcher<_Params, _Page, int>();

void main() {
  // =====================================================================
  // A1 — fresh dispatcher
  // =====================================================================
  group('ACAnchoredDispatcher — fresh (A1)', () {
    late ACAnchoredDispatcher<_Params, _Page, int> dispatcher;

    setUp(() {
      dispatcher = _build();
    });

    tearDown(() {
      dispatcher.dispose();
    });

    test('freshDispatcher_allListsEmpty_flagsFalse_notLoading', () {
      // Arrange & Act — nothing loaded yet.

      // Assert
      expect(dispatcher.itemsOlder, isEmpty);
      expect(dispatcher.itemsNewer, isEmpty);
      expect(dispatcher.items, isEmpty);
      expect(dispatcher.hasMoreOlder, isFalse);
      expect(dispatcher.hasMoreNewer, isFalse);
      expect(dispatcher.isLoadingOlder, isFalse);
      expect(dispatcher.isLoadingNewer, isFalse);
      expect(dispatcher.isLoadingAround, isFalse);
    });

    test('freshDispatcher_isChangeNotifier', () {
      // Arrange & Act & Assert
      expect(dispatcher, isA<ChangeNotifier>());
    });
  });

  // =====================================================================
  // A2 — loadAround
  // =====================================================================
  group('ACAnchoredDispatcher — loadAround (A2)', () {
    late ACAnchoredDispatcher<_Params, _Page, int> dispatcher;

    setUp(() {
      dispatcher = _build();
    });

    tearDown(() {
      dispatcher.dispose();
    });

    test('loadAround_seedsCenterIntoNewer_appliesBothFlags_storesLastAround',
        () async {
      // Arrange
      const page = _Around(
        items: <int>[1, 2, 3],
        hasMoreOlder: true,
        hasMoreNewer: true,
      );
      final loader = FakeLoader<ACAnchoredPage<int>>();
      loader.enqueueValue(page);

      // Act
      await dispatcher.loadAround(
        params: const _Params(),
        load: loader.call,
      );

      // Assert — center seeded into the newer side, older cleared.
      expect(dispatcher.itemsNewer, equals(<int>[1, 2, 3]));
      expect(dispatcher.itemsOlder, isEmpty);
      expect(dispatcher.items, equals(<int>[1, 2, 3]));
      expect(dispatcher.hasMoreOlder, isTrue);
      expect(dispatcher.hasMoreNewer, isTrue);
      expect(dispatcher.lastAround, same(page));
      expect(dispatcher.isLoadingAround, isFalse);
    });

    test('secondLoadAround_reseedsTheNewerSide', () async {
      // Arrange — a first around load, then a second with different data.
      final loader = FakeLoader<ACAnchoredPage<int>>();
      loader.enqueueValue(
        const _Around(items: <int>[1, 2], hasMoreOlder: true, hasMoreNewer: true),
      );
      loader.enqueueValue(
        const _Around(items: <int>[8, 9], hasMoreOlder: false, hasMoreNewer: false),
      );
      await dispatcher.loadAround(
        params: const _Params(),
        load: loader.call,
      );

      // Act
      await dispatcher.loadAround(
        params: const _Params(),
        load: loader.call,
      );

      // Assert — reseeded, not merged; flags follow the newest page.
      expect(dispatcher.itemsNewer, equals(<int>[8, 9]));
      expect(dispatcher.items, equals(<int>[8, 9]));
      expect(dispatcher.hasMoreOlder, isFalse);
      expect(dispatcher.hasMoreNewer, isFalse);
    });

    test('staleAroundResult_isIgnored_whenPreemptedByNewerAround', () async {
      // Arrange — a gated first around; a second around preempts it.
      final gate = Completer<ACAnchoredPage<int>>();
      Future<ACAnchoredPage<int>> slowAround(_Params _) => gate.future;
      final fresh = FakeLoader<ACAnchoredPage<int>>();
      fresh.enqueueValue(
        const _Around(items: <int>[5, 6], hasMoreOlder: false, hasMoreNewer: true),
      );

      // Act — start the gated around, then preempt with a fresh one.
      final staleFuture = dispatcher.loadAround(
        params: const _Params(),
        load: slowAround,
      );
      expect(dispatcher.isLoadingAround, isTrue);
      await dispatcher.loadAround(
        params: const _Params(),
        load: fresh.call,
      );

      // Release the stale load after preemption.
      gate.complete(
        const _Around(items: <int>[99], hasMoreOlder: true, hasMoreNewer: true),
      );
      await staleFuture;

      // Assert — the fresh result stands; the stale one never wrote state.
      expect(dispatcher.itemsNewer, equals(<int>[5, 6]));
      expect(dispatcher.hasMoreOlder, isFalse);
      expect(dispatcher.hasMoreNewer, isTrue);
    });
  });

  // =====================================================================
  // A3 — loadOlder
  // =====================================================================
  group('ACAnchoredDispatcher — loadOlder (A3)', () {
    late ACAnchoredDispatcher<_Params, _Page, int> dispatcher;

    setUp(() {
      dispatcher = _build();
    });

    tearDown(() {
      dispatcher.dispose();
    });

    Future<void> seedAround() {
      final loader = FakeLoader<ACAnchoredPage<int>>();
      loader.enqueueValue(
        const _Around(items: <int>[1, 2, 3], hasMoreOlder: true, hasMoreNewer: true),
      );
      return dispatcher.loadAround(
        params: const _Params(),
        load: loader.call,
      );
    }

    test('loadOlder_appendsToOlder_mergedOrderIsReverseOlderPlusNewer', () async {
      // Arrange — around seeds newer [1,2,3] with hasMoreOlder=true.
      await seedAround();
      final loader = FakeLoader<_Page>();
      loader.enqueueValue(const _Page(items: <int>[90, 80], hasMore: true));

      // Act
      await dispatcher.loadOlder(
        params: const _Params(),
        load: loader.call,
      );

      // Assert — older grows closest-older -> oldest; merged is reverse++newer.
      expect(dispatcher.itemsOlder, equals(<int>[90, 80]));
      expect(dispatcher.items, equals(<int>[80, 90, 1, 2, 3]));
      expect(dispatcher.hasMoreOlder, isTrue);
    });

    test('loadOlder_isNoOp_whenHasMoreOlderFalse', () async {
      // Arrange — hasMoreOlder defaults to false on a fresh dispatcher.
      final loader = FakeLoader<_Page>();
      loader.enqueueValue(const _Page(items: <int>[1], hasMore: true));
      expect(dispatcher.hasMoreOlder, isFalse);

      // Act
      await dispatcher.loadOlder(
        params: const _Params(),
        load: loader.call,
      );

      // Assert
      expect(loader.callCount, equals(0));
      expect(dispatcher.itemsOlder, isEmpty);
    });

    test('loadOlder_forceTrue_bypassesHasMoreOlderGuard', () async {
      // Arrange — hasMoreOlder=false, but force must load anyway.
      final loader = FakeLoader<_Page>();
      loader.enqueueValue(const _Page(items: <int>[7], hasMore: true));
      expect(dispatcher.hasMoreOlder, isFalse);

      // Act
      await dispatcher.loadOlder(
        params: const _Params(),
        load: loader.call,
        force: true,
      );

      // Assert
      expect(loader.callCount, equals(1));
      expect(dispatcher.itemsOlder, equals(<int>[7]));
    });

    test('secondLoadOlder_whileFirstInFlight_isNoOp', () async {
      // Arrange — around seeds hasMoreOlder=true, then a gated loadOlder.
      await seedAround();
      final gate = Completer<_Page>();
      Future<_Page> slowLoad(_Params _) => gate.future;
      final second = FakeLoader<_Page>();
      second.enqueueValue(const _Page(items: <int>[1], hasMore: true));

      // Act — start one loadOlder, then a concurrent one.
      final first = dispatcher.loadOlder(
        params: const _Params(),
        load: slowLoad,
      );
      expect(dispatcher.isLoadingOlder, isTrue);
      await dispatcher.loadOlder(
        params: const _Params(),
        load: second.call,
      );

      // Release the first.
      gate.complete(const _Page(items: <int>[50], hasMore: true));
      await first;

      // Assert — the concurrent loader never ran.
      expect(second.callCount, equals(0));
      expect(dispatcher.itemsOlder, equals(<int>[50]));
    });
  });

  // =====================================================================
  // A4 — loadNewer
  // =====================================================================
  group('ACAnchoredDispatcher — loadNewer (A4)', () {
    late ACAnchoredDispatcher<_Params, _Page, int> dispatcher;

    setUp(() {
      dispatcher = _build();
    });

    tearDown(() {
      dispatcher.dispose();
    });

    Future<void> seedAround() {
      final loader = FakeLoader<ACAnchoredPage<int>>();
      loader.enqueueValue(
        const _Around(items: <int>[1, 2, 3], hasMoreOlder: true, hasMoreNewer: true),
      );
      return dispatcher.loadAround(
        params: const _Params(),
        load: loader.call,
      );
    }

    test('loadNewer_appendsToNewer_appliesHasMoreFromPage', () async {
      // Arrange
      await seedAround();
      final loader = FakeLoader<_Page>();
      loader.enqueueValue(const _Page(items: <int>[4, 5], hasMore: false));

      // Act
      await dispatcher.loadNewer(
        params: const _Params(),
        load: loader.call,
      );

      // Assert
      expect(dispatcher.itemsNewer, equals(<int>[1, 2, 3, 4, 5]));
      expect(dispatcher.hasMoreNewer, isFalse);
      expect(dispatcher.items, equals(<int>[1, 2, 3, 4, 5]));
    });

    test('loadOlderAndLoadNewer_runConcurrently_bothInFlightIndependently',
        () async {
      // Arrange — around seeds both hasMore flags true; gate each side.
      await seedAround();
      final olderGate = Completer<_Page>();
      final newerGate = Completer<_Page>();
      Future<_Page> slowOlder(_Params _) => olderGate.future;
      Future<_Page> slowNewer(_Params _) => newerGate.future;

      // Act — start both sides simultaneously.
      final olderFuture = dispatcher.loadOlder(
        params: const _Params(),
        load: slowOlder,
      );
      final newerFuture = dispatcher.loadNewer(
        params: const _Params(),
        load: slowNewer,
      );

      // Assert — both sides load in parallel, neither blocks the other.
      expect(dispatcher.isLoadingOlder, isTrue);
      expect(dispatcher.isLoadingNewer, isTrue);

      // Release both.
      olderGate.complete(const _Page(items: <int>[70], hasMore: true));
      newerGate.complete(const _Page(items: <int>[8], hasMore: true));
      await Future.wait<void>(<Future<void>>[olderFuture, newerFuture]);

      // Assert — each side appended to its own list.
      expect(dispatcher.itemsOlder, equals(<int>[70]));
      expect(dispatcher.itemsNewer, equals(<int>[1, 2, 3, 8]));
      expect(dispatcher.items, equals(<int>[70, 1, 2, 3, 8]));
    });
  });

  // =====================================================================
  // A5 — merged list & immutability
  // =====================================================================
  group('ACAnchoredDispatcher — merged list & immutability (A5)', () {
    late ACAnchoredDispatcher<_Params, _Page, int> dispatcher;

    setUp(() {
      dispatcher = _build();
    });

    tearDown(() {
      dispatcher.dispose();
    });

    test('items_equalsReverseOlderPlusNewer', () async {
      // Arrange — seed newer via around, then grow older.
      final around = FakeLoader<ACAnchoredPage<int>>();
      around.enqueueValue(
        const _Around(items: <int>[1, 2], hasMoreOlder: true, hasMoreNewer: true),
      );
      await dispatcher.loadAround(
        params: const _Params(),
        load: around.call,
      );
      final older = FakeLoader<_Page>();
      older.enqueueValue(const _Page(items: <int>[10, 20, 30], hasMore: true));
      await dispatcher.loadOlder(
        params: const _Params(),
        load: older.call,
      );

      // Act
      final merged = dispatcher.items;

      // Assert — reverse([10,20,30]) ++ [1,2].
      expect(
        merged,
        equals(<int>[
          ...dispatcher.itemsOlder.reversed,
          ...dispatcher.itemsNewer,
        ]),
      );
      expect(merged, equals(<int>[30, 20, 10, 1, 2]));
    });

    test('items_isUnmodifiable', () {
      // Arrange
      final items = dispatcher.items;

      // Act & Assert
      expect(() => items.add(1), throwsUnsupportedError);
    });

    test('itemsOlder_isUnmodifiable', () {
      // Arrange
      final older = dispatcher.itemsOlder;

      // Act & Assert
      expect(() => older.add(1), throwsUnsupportedError);
    });

    test('itemsNewer_isUnmodifiable', () {
      // Arrange
      final newer = dispatcher.itemsNewer;

      // Act & Assert
      expect(() => newer.add(1), throwsUnsupportedError);
    });
  });
}
