// ignore_for_file: cascade_invocations, unused_element_parameter, prefer_const_constructors
import 'dart:async';

import 'package:appcraft_list_loading_flutter/appcraft_list_loading_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_loader.dart';

/// Around-page model for `loadAround`.
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

/// Per-side page model.
final class _Page with ACPage<int> {
  const _Page({required this.items, required this.hasMore});

  @override
  final List<int> items;
  @override
  final bool hasMore;
}

/// Minimal params.
final class _Params with ACParamsMixin {
  const _Params({this.limit, this.query});

  @override
  final int? limit;
  @override
  final String? query;
}

ACAnchoredDispatcher<_Params, _Page, int> _build() =>
    ACAnchoredDispatcher<_Params, _Page, int>();

/// Seeds the newer side via `loadAround` with both `hasMore` flags true.
Future<void> _seedAround(
  ACAnchoredDispatcher<_Params, _Page, int> dispatcher,
) {
  final loader = FakeLoader<ACAnchoredPage<int>>();
  loader.enqueueValue(
    const _Around(items: <int>[1, 2, 3], hasMoreOlder: true, hasMoreNewer: true),
  );
  return dispatcher.loadAround(
    params: const _Params(),
    load: loader.call,
  );
}

void main() {
  // =====================================================================
  // A6 — separate per-side loading state
  // =====================================================================
  group('ACAnchoredDispatcher — separate loading state (A6)', () {
    late ACAnchoredDispatcher<_Params, _Page, int> dispatcher;

    setUp(() {
      dispatcher = _build();
    });

    tearDown(() {
      dispatcher.dispose();
    });

    test('loadingOlder_doesNotAffectIsLoadingNewer', () async {
      // Arrange — around seeds both sides loadable; gate the older side.
      await _seedAround(dispatcher);
      final gate = Completer<_Page>();
      Future<_Page> slowOlder(_Params _) => gate.future;

      // Act
      final future = dispatcher.loadOlder(
        params: const _Params(),
        load: slowOlder,
      );

      // Assert — only the older flag flips.
      expect(dispatcher.isLoadingOlder, isTrue);
      expect(dispatcher.isLoadingNewer, isFalse);

      // Cleanup
      gate.complete(const _Page(items: <int>[9], hasMore: true));
      await future;
    });

    test('perSideListenables_notifyIndependently_onLoadOlder', () async {
      // Arrange
      await _seedAround(dispatcher);
      var olderTicks = 0;
      var newerTicks = 0;
      dispatcher.loadingOlderListenable.addListener(() => olderTicks++);
      dispatcher.loadingNewerListenable.addListener(() => newerTicks++);
      final loader = FakeLoader<_Page>();
      loader.enqueueValue(const _Page(items: <int>[9], hasMore: true));

      // Act
      await dispatcher.loadOlder(
        params: const _Params(),
        load: loader.call,
      );

      // Assert — the older listenable fired (true then false); newer silent.
      expect(olderTicks, greaterThan(0));
      expect(newerTicks, equals(0));
    });

    test('loadAround_isLoadingAroundTrueDuringLoad_falseAfter_listenableTicks',
        () async {
      // Arrange — a gated around load; record every around-loading transition.
      final gate = Completer<ACAnchoredPage<int>>();
      Future<ACAnchoredPage<int>> slow(_Params _) => gate.future;
      final transitions = <bool>[];
      dispatcher.loadingAroundListenable
          .addListener(() => transitions.add(dispatcher.isLoadingAround));

      // Act — start the around load; the flag flips synchronously.
      final future = dispatcher.loadAround(
        params: const _Params(),
        load: slow,
      );

      // Assert — in-flight.
      expect(dispatcher.isLoadingAround, isTrue);
      expect(dispatcher.loadingAroundListenable, isA<ValueListenable<bool>>());

      // Release the gate and finish.
      gate.complete(
        const _Around(items: <int>[1], hasMoreOlder: false, hasMoreNewer: false),
      );
      await future;

      // Assert — settled to false; the listenable saw true then false.
      expect(dispatcher.isLoadingAround, isFalse);
      expect(transitions, equals(<bool>[true, false]));
    });
  });

  // =====================================================================
  // A7 — errors isolated per side
  // =====================================================================
  group('ACAnchoredDispatcher — per-side errors (A7)', () {
    late ACAnchoredDispatcher<_Params, _Page, int> dispatcher;

    setUp(() {
      dispatcher = _build();
    });

    tearDown(() {
      dispatcher.dispose();
    });

    test('loadOlderThrows_capturesLastErrorOlder_leavesNewerUntouched',
        () async {
      // Arrange — enable the older side, then fail it.
      dispatcher.hasMoreOlder = true;
      final loader = FakeLoader<_Page>();
      final failure = Exception('older down');
      loader.enqueueError(failure);

      // Act & Assert — exception propagated to the caller.
      await expectLater(
        dispatcher.loadOlder(
          params: const _Params(),
          load: loader.call,
        ),
        throwsA(same(failure)),
      );

      // Assert — error captured on the older channel only.
      expect(dispatcher.lastErrorOlder, same(failure));
      expect(dispatcher.lastErrorNewer, isNull);
      expect(dispatcher.isLoadingOlder, isFalse);
    });

    test('loadNewerThrows_capturesLastErrorNewer_leavesOlderUntouched',
        () async {
      // Arrange
      dispatcher.hasMoreNewer = true;
      final loader = FakeLoader<_Page>();
      final failure = Exception('newer down');
      loader.enqueueError(failure);

      // Act & Assert
      await expectLater(
        dispatcher.loadNewer(
          params: const _Params(),
          load: loader.call,
        ),
        throwsA(same(failure)),
      );

      // Assert
      expect(dispatcher.lastErrorNewer, same(failure));
      expect(dispatcher.lastErrorOlder, isNull);
      expect(dispatcher.isLoadingNewer, isFalse);
    });

    test('retryOlder_repeatsOlderSide_andSucceeds', () async {
      // Arrange — a failing older load then a successful retry.
      dispatcher.hasMoreOlder = true;
      final loader = FakeLoader<_Page>();
      final failure = Exception('boom');
      loader.enqueueError(failure);
      loader.enqueueValue(const _Page(items: <int>[42], hasMore: true));
      await expectLater(
        dispatcher.loadOlder(
          params: const _Params(),
          load: loader.call,
        ),
        throwsA(same(failure)),
      );

      // Act
      await dispatcher.retryOlder();

      // Assert — the older side reran; error cleared.
      expect(loader.callCount, equals(2));
      expect(dispatcher.itemsOlder, equals(<int>[42]));
      expect(dispatcher.lastErrorOlder, isNull);
    });

    test('retryNewer_repeatsNewerSide_andSucceeds', () async {
      // Arrange
      dispatcher.hasMoreNewer = true;
      final loader = FakeLoader<_Page>();
      final failure = Exception('boom');
      loader.enqueueError(failure);
      loader.enqueueValue(const _Page(items: <int>[7], hasMore: true));
      await expectLater(
        dispatcher.loadNewer(
          params: const _Params(),
          load: loader.call,
        ),
        throwsA(same(failure)),
      );

      // Act
      await dispatcher.retryNewer();

      // Assert
      expect(loader.callCount, equals(2));
      expect(dispatcher.itemsNewer, equals(<int>[7]));
      expect(dispatcher.lastErrorNewer, isNull);
    });

    test('loadAroundThrows_propagates_capturesLastErrorAround_notLoading',
        () async {
      // Arrange — the around loader fails; watch the around error channel.
      final loader = FakeLoader<ACAnchoredPage<int>>();
      final failure = Exception('around down');
      loader.enqueueError(failure);
      var aroundErrorTicks = 0;
      dispatcher.errorAroundListenable.addListener(() => aroundErrorTicks++);

      // Act & Assert — exception propagated to the caller.
      await expectLater(
        dispatcher.loadAround(
          params: const _Params(),
          load: loader.call,
        ),
        throwsA(same(failure)),
      );

      // Assert — error captured; loading reset; the around channel notified.
      expect(dispatcher.lastErrorAround, same(failure));
      expect(dispatcher.isLoadingAround, isFalse);
      expect(aroundErrorTicks, greaterThan(0));
    });

    test('loadAroundSucceedsAfterError_clearsLastErrorAround', () async {
      // Arrange — a failing around, then a successful one.
      final loader = FakeLoader<ACAnchoredPage<int>>();
      final failure = Exception('around down');
      loader.enqueueError(failure);
      loader.enqueueValue(
        const _Around(items: <int>[1], hasMoreOlder: false, hasMoreNewer: false),
      );
      await expectLater(
        dispatcher.loadAround(
          params: const _Params(),
          load: loader.call,
        ),
        throwsA(same(failure)),
      );
      expect(dispatcher.lastErrorAround, same(failure));

      // Act — a subsequent successful around load.
      await dispatcher.loadAround(
        params: const _Params(),
        load: loader.call,
      );

      // Assert — the around error is cleared on success.
      expect(dispatcher.lastErrorAround, isNull);
      expect(dispatcher.itemsNewer, equals(<int>[1]));
    });

    test('errorListenables_areValueListenables_notifyOnTheirOwnSide', () async {
      // Arrange
      expect(
          dispatcher.errorOlderListenable, isA<ValueListenable<Object?>>());
      expect(
          dispatcher.errorNewerListenable, isA<ValueListenable<Object?>>());
      expect(
          dispatcher.errorAroundListenable, isA<ValueListenable<Object?>>());
      dispatcher.hasMoreOlder = true;
      var olderTicks = 0;
      var newerTicks = 0;
      var aroundTicks = 0;
      dispatcher.errorOlderListenable.addListener(() => olderTicks++);
      dispatcher.errorNewerListenable.addListener(() => newerTicks++);
      dispatcher.errorAroundListenable.addListener(() => aroundTicks++);
      final loader = FakeLoader<_Page>();
      loader.enqueueError(Exception('older'));

      // Act — only the older side fails.
      await expectLater(
        dispatcher.loadOlder(
          params: const _Params(),
          load: loader.call,
        ),
        throwsA(isA<Exception>()),
      );

      // Assert — only the older error channel fired.
      expect(olderTicks, greaterThan(0));
      expect(newerTicks, equals(0));
      expect(aroundTicks, equals(0));
    });
  });

  // =====================================================================
  // A8 — realtime mutate
  // =====================================================================
  group('ACAnchoredDispatcher — mutate (A8)', () {
    late ACAnchoredDispatcher<_Params, _Page, int> dispatcher;
    late int notifyCount;

    setUp(() {
      dispatcher = _build();
      notifyCount = 0;
      dispatcher.addListener(() => notifyCount++);
    });

    tearDown(() {
      dispatcher.dispose();
    });

    test('mutateNewer_addsItem_appearsInNewerAndMerged_notifiesOnce', () async {
      // Arrange
      await _seedAround(dispatcher);
      final baseline = notifyCount;

      // Act
      dispatcher.mutateNewer((l) => l.add(99));

      // Assert
      expect(dispatcher.itemsNewer, equals(<int>[1, 2, 3, 99]));
      expect(dispatcher.items, equals(<int>[1, 2, 3, 99]));
      expect(notifyCount - baseline, equals(1));
    });

    test('mutateNewer_compositeEdit_notifiesOnce', () async {
      // Arrange
      await _seedAround(dispatcher);
      final baseline = notifyCount;

      // Act — several edits inside a single mutate.
      dispatcher.mutateNewer((l) => l
        ..add(4)
        ..add(5)
        ..removeAt(0));

      // Assert — one notification for the whole batch.
      expect(dispatcher.itemsNewer, equals(<int>[2, 3, 4, 5]));
      expect(notifyCount - baseline, equals(1));
    });

    test('mutateOlder_participatesInMergedReverse', () async {
      // Arrange
      await _seedAround(dispatcher);

      // Act — older grows; merged reverses it before the newer side.
      dispatcher.mutateOlder((l) => l
        ..add(10)
        ..add(20));

      // Assert
      expect(dispatcher.itemsOlder, equals(<int>[10, 20]));
      expect(dispatcher.items, equals(<int>[20, 10, 1, 2, 3]));
    });

    test('directMutationOfNewer_throwsUnsupportedError', () async {
      // Arrange
      await _seedAround(dispatcher);

      // Act & Assert
      expect(() => dispatcher.itemsNewer.add(1), throwsUnsupportedError);
      expect(() => dispatcher.items.add(1), throwsUnsupportedError);
    });

    test('mutateAfterDispose_isNoOp', () {
      // Arrange
      dispatcher.dispose();

      // Act & Assert — no throw, no effect.
      expect(
        () => dispatcher.mutateNewer((l) => l.add(1)),
        returnsNormally,
      );
      expect(dispatcher.itemsNewer, isEmpty);
    });
  });

  // =====================================================================
  // A9 — dispose idempotent
  // =====================================================================
  group('ACAnchoredDispatcher — dispose (A9)', () {
    test('dispose_isIdempotent', () {
      // Arrange
      final dispatcher = _build();

      // Act & Assert — a repeated dispose is a safe no-op.
      dispatcher.dispose();
      expect(dispatcher.dispose, returnsNormally);
    });
  });

  // =====================================================================
  // A10 — notify on items change of either side
  // =====================================================================
  group('ACAnchoredDispatcher — notify (A10)', () {
    late ACAnchoredDispatcher<_Params, _Page, int> dispatcher;
    late int notifyCount;

    setUp(() {
      dispatcher = _build();
      notifyCount = 0;
      dispatcher.addListener(() => notifyCount++);
    });

    tearDown(() {
      dispatcher.dispose();
    });

    test('itemsChangeOnEitherSide_notifiesListeners', () async {
      // Arrange
      await _seedAround(dispatcher);
      final afterAround = notifyCount;

      // Act — a newer-side change.
      dispatcher.mutateNewer((l) => l.add(4));
      final afterNewer = notifyCount;

      // Act — an older-side change.
      dispatcher.mutateOlder((l) => l.add(90));

      // Assert — both sides forward item-change notifications.
      expect(afterAround, greaterThan(0),
          reason: 'seeding the newer side notifies');
      expect(afterNewer - afterAround, equals(1));
      expect(notifyCount - afterNewer, equals(1));
    });

    test('changingHasMoreFlag_doesNotNotify', () {
      // Arrange — a fresh dispatcher, no item changes.
      final baseline = notifyCount;

      // Act — flip the guard flags only.
      dispatcher.hasMoreOlder = true;
      dispatcher.hasMoreNewer = true;

      // Assert — flag changes alone do not notify the merged view.
      expect(notifyCount, equals(baseline));
    });
  });

  // =====================================================================
  // A11 — delegating result getters
  // =====================================================================
  group('ACAnchoredDispatcher — delegating getters (A11)', () {
    late ACAnchoredDispatcher<_Params, _Page, int> dispatcher;

    setUp(() {
      dispatcher = _build();
    });

    tearDown(() {
      dispatcher.dispose();
    });

    test('lastResultOlderAndNewer_mirrorTheReturnedSidePages', () async {
      // Arrange — around seeds both sides loadable; lastAround is the center.
      const around = _Around(
        items: <int>[1, 2, 3],
        hasMoreOlder: true,
        hasMoreNewer: true,
      );
      final aroundLoader = FakeLoader<ACAnchoredPage<int>>();
      aroundLoader.enqueueValue(around);
      await dispatcher.loadAround(
        params: const _Params(),
        load: aroundLoader.call,
      );

      // Assert — lastAround is the seeded center; sides not yet loaded.
      expect(dispatcher.lastAround, same(around));
      expect(dispatcher.lastResultOlder, isNull);
      expect(dispatcher.lastResultNewer, isNull);

      // Act — load each side once.
      const olderPage = _Page(items: <int>[90], hasMore: true);
      final olderLoader = FakeLoader<_Page>();
      olderLoader.enqueueValue(olderPage);
      await dispatcher.loadOlder(
        params: const _Params(),
        load: olderLoader.call,
      );
      const newerPage = _Page(items: <int>[8], hasMore: false);
      final newerLoader = FakeLoader<_Page>();
      newerLoader.enqueueValue(newerPage);
      await dispatcher.loadNewer(
        params: const _Params(),
        load: newerLoader.call,
      );

      // Assert — each getter mirrors the page returned by its side.
      expect(dispatcher.lastResultOlder, same(olderPage));
      expect(dispatcher.lastResultNewer, same(newerPage));
      expect(dispatcher.lastAround, same(around));
    });
  });

  // =====================================================================
  // A12 — cancel active loads
  // =====================================================================
  group('ACAnchoredDispatcher — cancel (A12)', () {
    late ACAnchoredDispatcher<_Params, _Page, int> dispatcher;

    setUp(() {
      dispatcher = _build();
    });

    tearDown(() {
      dispatcher.dispose();
    });

    test('cancel_duringSideLoads_stopsLoading_keepsItems', () async {
      // Arrange — seed [1,2,3] into newer, then gate both sides in-flight.
      await _seedAround(dispatcher);
      final olderGate = Completer<_Page>();
      final newerGate = Completer<_Page>();
      Future<_Page> slowOlder(_Params _) => olderGate.future;
      Future<_Page> slowNewer(_Params _) => newerGate.future;
      final olderFuture = dispatcher.loadOlder(
        params: const _Params(),
        load: slowOlder,
      );
      final newerFuture = dispatcher.loadNewer(
        params: const _Params(),
        load: slowNewer,
      );
      expect(dispatcher.isLoadingOlder, isTrue);
      expect(dispatcher.isLoadingNewer, isTrue);

      // Act
      await dispatcher.cancel();

      // Assert — both side loads interrupted; collection state untouched.
      expect(dispatcher.isLoadingOlder, isFalse);
      expect(dispatcher.isLoadingNewer, isFalse);
      expect(dispatcher.itemsNewer, equals(<int>[1, 2, 3]));
      expect(dispatcher.itemsOlder, isEmpty);

      // Cleanup — release the gated loaders; their stale results are ignored.
      olderGate.complete(const _Page(items: <int>[70], hasMore: true));
      newerGate.complete(const _Page(items: <int>[8], hasMore: true));
      await Future.wait<void>(<Future<void>>[olderFuture, newerFuture]);
    });

    test('cancel_duringAroundLoad_stopsAroundLoading_keepsItems', () async {
      // Arrange — seed [1,2,3], then start a gated around load.
      await _seedAround(dispatcher);
      final gate = Completer<ACAnchoredPage<int>>();
      Future<ACAnchoredPage<int>> slow(_Params _) => gate.future;
      final future = dispatcher.loadAround(
        params: const _Params(),
        load: slow,
      );
      expect(dispatcher.isLoadingAround, isTrue);
      // Let loadAround drain its pre-cancel awaits and park on the loader,
      // so the around strategy has an active operation to cancel.
      await Future<void>.delayed(Duration.zero);

      // Act
      await dispatcher.cancel();
      // Release the now-stale gate; its result must not write state.
      gate.complete(
        const _Around(items: <int>[99], hasMoreOlder: true, hasMoreNewer: true),
      );
      await future;

      // Assert — around loading stopped; seeded items untouched.
      expect(dispatcher.isLoadingAround, isFalse);
      expect(dispatcher.itemsNewer, equals(<int>[1, 2, 3]));
    });
  });
}
