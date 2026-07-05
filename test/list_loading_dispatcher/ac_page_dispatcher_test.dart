// ignore_for_file: cascade_invocations, unused_element_parameter, prefer_const_constructors
import 'dart:async';

import 'package:appcraft_list_loading_flutter/src/ac_page.dart';
import 'package:appcraft_list_loading_flutter/src/ac_page_dispatcher.dart';
import 'package:appcraft_list_loading_flutter/src/ac_params.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_loader.dart';

/// Params for the DTO scenario. `ACPageDispatcher` never reads pagination
/// fields itself — `hasMore` comes from the page model — so only [query] is
/// meaningful here; [limit]/[cursor] are carried through to the loader.
final class _TestParams with ACParamsMixin {
  const _TestParams({this.limit, this.query, this.cursor});

  @override
  final int? limit;
  @override
  final String? query;

  /// Cursor for cursor-based pagination — passed to the loader as-is.
  final String? cursor;
}

/// Page-response DTO mixing in [ACPage]. Besides `items`/`hasMore` it carries
/// a [nextCursor] to prove `lastResult` exposes the whole model (metadata).
final class _FakePage<T> with ACPage<T> {
  const _FakePage({
    required this.items,
    required this.hasMore,
    this.nextCursor,
  });

  @override
  final List<T> items;
  @override
  final bool hasMore;

  /// Cursor/metadata reachable via `dispatcher.lastResult`.
  final String? nextCursor;
}

ACPageDispatcher<_TestParams, _FakePage<int>, int> _buildDispatcher() =>
    ACPageDispatcher<_TestParams, _FakePage<int>, int>();

void main() {
  group('ACPageDispatcher — initial state (US1)', () {
    late ACPageDispatcher<_TestParams, _FakePage<int>, int> dispatcher;

    setUp(() {
      dispatcher = _buildDispatcher();
    });

    tearDown(() {
      dispatcher.dispose();
    });

    test('fresh dispatcher: items empty, lastResult null, isLoading false', () {
      // Arrange & Act — dispatcher built in setUp.

      // Assert
      expect(dispatcher.items, isEmpty);
      expect(dispatcher.lastResult, isNull);
      expect(dispatcher.isLoading, isFalse);
    });

    test('fresh dispatcher reports hasMore=false (before first load)', () {
      // Arrange & Act & Assert
      expect(dispatcher.hasMore, isFalse);
    });

    test('is a ChangeNotifier / Listenable', () {
      // Arrange & Act & Assert
      expect(dispatcher, isA<ChangeNotifier>());
      expect(dispatcher, isA<Listenable>());
    });

    test('items getter returns an unmodifiable view (D-01)', () {
      // Arrange
      final items = dispatcher.items;

      // Act & Assert
      expect(() => items.add(42), throwsUnsupportedError);
    });
  });

  group('ACPageDispatcher — reload extracts from the model (US1)', () {
    late ACPageDispatcher<_TestParams, _FakePage<int>, int> dispatcher;
    late FakeLoader<_FakePage<int>> loader;
    late int notifyCount;

    setUp(() {
      dispatcher = _buildDispatcher();
      loader = FakeLoader<_FakePage<int>>();
      notifyCount = 0;
      dispatcher.addListener(() => notifyCount++);
    });

    tearDown(() {
      dispatcher.dispose();
    });

    test(
        'reload uses model.items/model.hasMore, keeps model as lastResult, '
        'notifies once (D-02)', () async {
      // Arrange — page1 with hasMore=true, plus cursor metadata.
      const page1 = _FakePage<int>(
        items: <int>[1, 2],
        hasMore: true,
        nextCursor: 'c1',
      );
      loader.enqueueValue(page1);

      // Act
      final future = dispatcher.reload(
        params: const _TestParams(),
        load: loader.call,
      );
      // Between start and completion the dispatcher must be loading.
      expect(dispatcher.isLoading, isTrue);
      await future;

      // Assert — items and hasMore come straight from the model.
      expect(dispatcher.items, equals(<int>[1, 2]));
      expect(dispatcher.hasMore, isTrue);
      expect(dispatcher.isLoading, isFalse);
      expect(dispatcher.lastResult, same(page1),
          reason: 'lastResult is the exact model reference (metadata access)');
      expect(dispatcher.lastResult?.nextCursor, equals('c1'));
      expect(loader.callCount, 1);
      expect(notifyCount, equals(1),
          reason: 'a successful reload must notify exactly once');
    });

    test('reload with hasMore=false in the model sets hasMore=false', () async {
      // Arrange — last page.
      loader.enqueueValue(
        const _FakePage<int>(items: <int>[42], hasMore: false),
      );

      // Act
      await dispatcher.reload(
        params: const _TestParams(),
        load: loader.call,
      );

      // Assert
      expect(dispatcher.items, equals(<int>[42]));
      expect(dispatcher.hasMore, isFalse,
          reason: 'hasMore is read from the model, not derived from a limit');
    });

    test('second reload replaces the accumulated items entirely', () async {
      // Arrange
      loader.enqueueValue(
        const _FakePage<int>(items: <int>[1, 2, 3], hasMore: true),
      );
      loader.enqueueValue(
        const _FakePage<int>(items: <int>[7, 8], hasMore: true),
      );
      await dispatcher.reload(
        params: const _TestParams(),
        load: loader.call,
      );

      // Act
      await dispatcher.reload(
        params: const _TestParams(),
        load: loader.call,
      );

      // Assert — items are replaced, not merged.
      expect(dispatcher.items, equals(<int>[7, 8]));
    });
  });

  group('ACPageDispatcher — loadMore appends (US1)', () {
    late ACPageDispatcher<_TestParams, _FakePage<int>, int> dispatcher;
    late FakeLoader<_FakePage<int>> loader;
    late int notifyCount;

    setUp(() {
      dispatcher = _buildDispatcher();
      loader = FakeLoader<_FakePage<int>>();
      notifyCount = 0;
      dispatcher.addListener(() => notifyCount++);
    });

    tearDown(() {
      dispatcher.dispose();
    });

    test(
        'loadMore appends model.items, updates hasMore and lastResult, '
        'notifies once (D-03)', () async {
      // Arrange — seed [a,b] with hasMore=true; next page is the last one.
      const page1 = _FakePage<int>(items: <int>[1, 2], hasMore: true);
      const page2 = _FakePage<int>(
        items: <int>[3],
        hasMore: false,
        nextCursor: 'end',
      );
      loader.enqueueValue(page1);
      loader.enqueueValue(page2);
      await dispatcher.reload(
        params: const _TestParams(),
        load: loader.call,
      );
      final countAfterReload = notifyCount;

      // Act
      await dispatcher.loadMore(
        params: const _TestParams(cursor: 'c1'),
        load: loader.call,
      );

      // Assert
      expect(dispatcher.items, equals(<int>[1, 2, 3]));
      expect(dispatcher.hasMore, isFalse,
          reason: 'hasMore follows the last page model');
      expect(dispatcher.lastResult, same(page2),
          reason: 'lastResult points to the most recent page');
      expect(notifyCount - countAfterReload, equals(1));
      expect(loader.callCount, 2);
    });
  });

  group('ACPageDispatcher — loadMore guards (US1)', () {
    late ACPageDispatcher<_TestParams, _FakePage<int>, int> dispatcher;
    late FakeLoader<_FakePage<int>> loader;

    setUp(() {
      dispatcher = _buildDispatcher();
      loader = FakeLoader<_FakePage<int>>();
    });

    tearDown(() {
      dispatcher.dispose();
    });

    test('loadMore is a no-op when hasMore=false — loader not invoked',
        () async {
      // Arrange — seed hasMore=false from the model.
      loader.enqueueValue(
        const _FakePage<int>(items: <int>[1], hasMore: false),
      );
      await dispatcher.reload(
        params: const _TestParams(),
        load: loader.call,
      );
      final callsBefore = loader.callCount;
      final itemsBefore = List<int>.from(dispatcher.items);
      var notifyAfter = 0;
      dispatcher.addListener(() => notifyAfter++);
      expect(dispatcher.hasMore, isFalse);

      // Act
      await dispatcher.loadMore(
        params: const _TestParams(),
        load: loader.call,
      );

      // Assert
      expect(loader.callCount, equals(callsBefore),
          reason: 'loader must not run when hasMore=false');
      expect(dispatcher.items, equals(itemsBefore));
      expect(notifyAfter, equals(0),
          reason: 'a no-op loadMore must not notify');
    });

    test('loadMore while another load is in flight is a no-op', () async {
      // Arrange — seed items + hasMore=true.
      loader.enqueueValue(
        const _FakePage<int>(items: <int>[1, 2], hasMore: true),
      );
      await dispatcher.reload(
        params: const _TestParams(),
        load: loader.call,
      );
      // The first loadMore blocks on a gate.
      final gate = Completer<_FakePage<int>>();
      Future<_FakePage<int>> slowLoad(_TestParams _) => gate.future;
      final secondLoader = FakeLoader<_FakePage<int>>();
      secondLoader.enqueueValue(
        const _FakePage<int>(items: <int>[9, 9], hasMore: true),
      );

      // Act — start one loadMore, then try a second concurrently.
      final firstFuture = dispatcher.loadMore(
        params: const _TestParams(),
        load: slowLoad,
      );
      expect(dispatcher.isLoading, isTrue);
      await dispatcher.loadMore(
        params: const _TestParams(),
        load: secondLoader.call,
      );

      // Release the first loadMore.
      gate.complete(
        const _FakePage<int>(items: <int>[3, 4], hasMore: true),
      );
      await firstFuture;

      // Assert
      expect(secondLoader.callCount, 0,
          reason: 'concurrent loadMore must not invoke the second loader');
      expect(dispatcher.items, equals(<int>[1, 2, 3, 4]));
    });

    test('loadMore after dispose is a no-op (loader not invoked)', () async {
      // Arrange
      dispatcher.dispose();
      loader.enqueueValue(
        const _FakePage<int>(items: <int>[1], hasMore: true),
      );

      // Act
      await dispatcher.loadMore(
        params: const _TestParams(),
        load: loader.call,
      );

      // Assert
      expect(loader.callCount, 0);
    });
  });
}
