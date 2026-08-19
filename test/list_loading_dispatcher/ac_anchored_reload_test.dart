// ignore_for_file: cascade_invocations, unused_element_parameter, prefer_const_constructors
import 'package:appcraft_list_loading_flutter/appcraft_list_loading_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_loader.dart';

/// Per-side page model: `hasMore` means «is there more **beyond this side's
/// edge**».
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

/// Seeds the window used across the scenarios below.
///
/// Anchor is `10`. Older side receives `[9, 8, 7]` (closest-older → oldest),
/// newer side receives `[10, 11]` (anchor → newest). The merged view must
/// therefore read `[7, 8, 9, 10, 11]`.
Future<void> _seedWindow(
  ACAnchoredDispatcher<_Params, _Page, int> dispatcher, {
  bool hasMoreOlder = true,
  bool hasMoreNewer = true,
}) async {
  await dispatcher.reloadOlder(
    params: const _Params(limit: 3),
    load: (_) async => _Page(items: const <int>[9, 8, 7], hasMore: hasMoreOlder),
  );
  await dispatcher.reloadNewer(
    params: const _Params(limit: 2),
    load: (_) async => _Page(items: const <int>[10, 11], hasMore: hasMoreNewer),
  );
}

void main() {
  // =====================================================================
  // US1 — the window around an anchor becomes expressible
  // =====================================================================
  group('ACAnchoredDispatcher — window seeding (US1/016)', () {
    late ACAnchoredDispatcher<_Params, _Page, int> dispatcher;

    setUp(() {
      dispatcher = _build();
    });

    tearDown(() {
      dispatcher.dispose();
    });

    test('reloadOlder_seedsOlderSideVerbatim_closestOlderToOldest', () async {
      // Act
      await dispatcher.reloadOlder(
        params: const _Params(limit: 3),
        load: (_) async => _Page(items: const <int>[9, 8, 7], hasMore: true),
      );

      // Assert — seeded verbatim, no hidden reversal inside the package.
      expect(dispatcher.itemsOlder, equals(<int>[9, 8, 7]));
    });

    test('reloadNewer_seedsNewerSideVerbatim_anchorToNewest', () async {
      // Act
      await dispatcher.reloadNewer(
        params: const _Params(limit: 2),
        load: (_) async => _Page(items: const <int>[10, 11], hasMore: false),
      );

      // Assert — the anchor belongs to the newer side.
      expect(dispatcher.itemsNewer, equals(<int>[10, 11]));
    });

    test('bothSidesSeeded_mergedViewIsChronological', () async {
      // Act
      await _seedWindow(dispatcher);

      // Assert — reverse(older) ++ newer.
      expect(dispatcher.itemsOlder, equals(<int>[9, 8, 7]));
      expect(dispatcher.itemsNewer, equals(<int>[10, 11]));
      expect(dispatcher.items, equals(<int>[7, 8, 9, 10, 11]));
    });

    test('olderSideIsNotEmptyAfterSeeding', () async {
      // This is the regression the whole feature exists for: before 1.1.0
      // the older side was unconditionally cleared by `loadAround`.

      // Act
      await _seedWindow(dispatcher);

      // Assert
      expect(dispatcher.itemsOlder, isNotEmpty);
    });

    test('mergedView_isUnmodifiable', () async {
      // Arrange
      await _seedWindow(dispatcher);

      // Act & Assert
      expect(
        () => dispatcher.items.add(99),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('anchorIsLastMessage_wholeHistoryStaysVisible', () async {
      // The reported consumer scenario: no unread messages, so the anchor is
      // the last message of the conversation and the newer side holds exactly
      // one element. The history must still be reachable through the older
      // side rather than falling off the edge.

      // Act
      await dispatcher.reloadOlder(
        params: const _Params(limit: 4),
        load: (_) async =>
            _Page(items: const <int>[9, 8, 7, 6], hasMore: false),
      );
      await dispatcher.reloadNewer(
        params: const _Params(limit: 1),
        load: (_) async => _Page(items: const <int>[10], hasMore: false),
      );

      // Assert
      expect(dispatcher.itemsNewer, equals(<int>[10]));
      expect(dispatcher.items, equals(<int>[6, 7, 8, 9, 10]));
    });

    test('seeding_notifiesSubscribers', () async {
      // Arrange
      var notifications = 0;
      dispatcher.addListener(() => notifications++);

      // Act
      await dispatcher.reloadOlder(
        params: const _Params(),
        load: (_) async => _Page(items: const <int>[9, 8], hasMore: false),
      );
      await dispatcher.reloadNewer(
        params: const _Params(),
        load: (_) async => _Page(items: const <int>[10], hasMore: false),
      );

      // Assert — one notification per side whose items changed.
      expect(notifications, 2);
    });

    test('reload_replacesSideContents_doesNotAppend', () async {
      // Arrange
      await dispatcher.reloadOlder(
        params: const _Params(),
        load: (_) async => _Page(items: const <int>[9, 8, 7], hasMore: true),
      );

      // Act — a second seed on the same side.
      await dispatcher.reloadOlder(
        params: const _Params(),
        load: (_) async => _Page(items: const <int>[5, 4], hasMore: false),
      );

      // Assert — replacement, not accumulation.
      expect(dispatcher.itemsOlder, equals(<int>[5, 4]));
    });

    test('seedingOneSide_leavesOppositeSideUntouched', () async {
      // Arrange
      await _seedWindow(dispatcher);

      // Act — reseed only the newer side.
      await dispatcher.reloadNewer(
        params: const _Params(),
        load: (_) async => _Page(items: const <int>[20, 21], hasMore: false),
      );

      // Assert
      expect(dispatcher.itemsOlder, equals(<int>[9, 8, 7]));
      expect(dispatcher.itemsNewer, equals(<int>[20, 21]));
    });

    test('seedingAfterDispose_isNoOp', () async {
      // Arrange
      final loader = FakeLoader<_Page>();
      loader.enqueueValue(const _Page(items: <int>[1], hasMore: false));
      dispatcher.dispose();

      // Act
      await dispatcher.reloadOlder(
        params: const _Params(),
        load: loader.call,
      );

      // Assert
      expect(loader.callCount, 0);

      // Re-create so tearDown's dispose stays a safe no-op.
      dispatcher = _build();
    });
  });

  // =====================================================================
  // US2 — the «is there more beyond the window» flags come from the pages
  // =====================================================================
  group('ACAnchoredDispatcher — hasMore flags after seeding (US2/016)', () {
    late ACAnchoredDispatcher<_Params, _Page, int> dispatcher;

    setUp(() {
      dispatcher = _build();
    });

    tearDown(() {
      dispatcher.dispose();
    });

    test('hasMoreOlder_takenFromOlderPage', () async {
      // Act
      await dispatcher.reloadOlder(
        params: const _Params(),
        load: (_) async => _Page(items: const <int>[9, 8], hasMore: true),
      );

      // Assert
      expect(dispatcher.hasMoreOlder, isTrue);
    });

    test('hasMoreNewer_takenFromNewerPage', () async {
      // Act
      await dispatcher.reloadNewer(
        params: const _Params(),
        load: (_) async => _Page(items: const <int>[10], hasMore: false),
      );

      // Assert
      expect(dispatcher.hasMoreNewer, isFalse);
    });

    test('bothFlags_independentlySourcedFromTheirOwnPage', () async {
      // Act — asymmetric flags: history continues, the feed ends.
      await _seedWindow(dispatcher, hasMoreOlder: true, hasMoreNewer: false);

      // Assert
      expect(dispatcher.hasMoreOlder, isTrue);
      expect(dispatcher.hasMoreNewer, isFalse);
    });

    test('seedingOneSide_doesNotChangeOppositeFlag', () async {
      // Arrange
      await _seedWindow(dispatcher, hasMoreOlder: true, hasMoreNewer: true);

      // Act — reseed only the newer side with hasMore == false.
      await dispatcher.reloadNewer(
        params: const _Params(),
        load: (_) async => _Page(items: const <int>[10], hasMore: false),
      );

      // Assert — the older flag is untouched.
      expect(dispatcher.hasMoreOlder, isTrue);
      expect(dispatcher.hasMoreNewer, isFalse);
    });

    test('hasMoreOlderFalse_blocksLoadOlderWithoutForce', () async {
      // Arrange — the older side reports it reached the end of history.
      await dispatcher.reloadOlder(
        params: const _Params(),
        load: (_) async => _Page(items: const <int>[9, 8], hasMore: false),
      );
      final loader = FakeLoader<_Page>();
      loader.enqueueValue(const _Page(items: <int>[7], hasMore: false));

      // Act
      await dispatcher.loadOlder(params: const _Params(), load: loader.call);

      // Assert — the guard held.
      expect(loader.callCount, 0);
      expect(dispatcher.itemsOlder, equals(<int>[9, 8]));
    });
  });

  // =====================================================================
  // US3 — edge loading keeps working from the window's borders
  // =====================================================================
  group('ACAnchoredDispatcher — edge loading after seeding (US3/016)', () {
    late ACAnchoredDispatcher<_Params, _Page, int> dispatcher;

    setUp(() {
      dispatcher = _build();
    });

    tearDown(() {
      dispatcher.dispose();
    });

    test('loadOlder_appendsToOlderTail_doesNotOverwriteSeed', () async {
      // Arrange
      await _seedWindow(dispatcher);

      // Act
      await dispatcher.loadOlder(
        params: const _Params(),
        load: (_) async => _Page(items: const <int>[6, 5], hasMore: false),
      );

      // Assert — appended, seed preserved.
      expect(dispatcher.itemsOlder, equals(<int>[9, 8, 7, 6, 5]));
    });

    test('loadNewer_appendsToNewerTail_doesNotOverwriteSeed', () async {
      // Arrange
      await _seedWindow(dispatcher);

      // Act
      await dispatcher.loadNewer(
        params: const _Params(),
        load: (_) async => _Page(items: const <int>[12], hasMore: false),
      );

      // Assert
      expect(dispatcher.itemsNewer, equals(<int>[10, 11, 12]));
    });

    test('bothEdgesLoaded_mergedViewStaysChronological', () async {
      // Arrange
      await _seedWindow(dispatcher);

      // Act
      await dispatcher.loadOlder(
        params: const _Params(),
        load: (_) async => _Page(items: const <int>[6, 5], hasMore: false),
      );
      await dispatcher.loadNewer(
        params: const _Params(),
        load: (_) async => _Page(items: const <int>[12], hasMore: false),
      );

      // Assert
      expect(
        dispatcher.items,
        equals(<int>[5, 6, 7, 8, 9, 10, 11, 12]),
      );
    });

    test('lastResultBothSides_notNullRightAfterSeeding', () async {
      // The seeds are real loads, so the initial cursors live in the same
      // members as every subsequent one — no separate source for page one.

      // Act
      await _seedWindow(dispatcher);

      // Assert
      expect(dispatcher.lastResultOlder, isNotNull);
      expect(dispatcher.lastResultNewer, isNotNull);
      expect(dispatcher.lastResultOlder!.items, equals(<int>[9, 8, 7]));
      expect(dispatcher.lastResultNewer!.items, equals(<int>[10, 11]));
    });

    test('lastResult_updatedByEdgeLoads', () async {
      // Arrange
      await _seedWindow(dispatcher);

      // Act
      await dispatcher.loadOlder(
        params: const _Params(),
        load: (_) async => _Page(items: const <int>[6, 5], hasMore: false),
      );

      // Assert — same member, now carrying the edge page.
      expect(dispatcher.lastResultOlder!.items, equals(<int>[6, 5]));
      expect(dispatcher.lastResultNewer!.items, equals(<int>[10, 11]));
    });
  });
}
