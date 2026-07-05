// ignore_for_file: cascade_invocations, unused_element_parameter, prefer_const_constructors
import 'dart:async';

import 'package:appcraft_list_loading_flutter/src/ac_page.dart';
import 'package:appcraft_list_loading_flutter/src/ac_page_dispatcher.dart';
import 'package:appcraft_list_loading_flutter/src/ac_params.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_loader.dart';

/// Params for the DTO scenario.
final class _TestParams with ACParamsMixin {
  const _TestParams({this.limit, this.query});

  @override
  final int? limit;
  @override
  final String? query;
}

/// Page-response DTO mixing in [ACPage].
final class _FakePage<T> with ACPage<T> {
  const _FakePage({required this.items, required this.hasMore});

  @override
  final List<T> items;
  @override
  final bool hasMore;
}

_FakePage<int> _page(List<int> items, {bool hasMore = true}) =>
    _FakePage<int>(items: items, hasMore: hasMore);

ACPageDispatcher<_TestParams, _FakePage<int>, int> _buildDispatcher() =>
    ACPageDispatcher<_TestParams, _FakePage<int>, int>();

void main() {
  // -------------------------------------------------------------------------
  // US2 — external, notifying mutation via `mutate` (M-01).
  // -------------------------------------------------------------------------
  group('ACPageDispatcher — mutate (US2, M-01)', () {
    late ACPageDispatcher<_TestParams, _FakePage<int>, int> dispatcher;
    late int notifyCount;

    setUp(() {
      dispatcher = _buildDispatcher();
      notifyCount = 0;
      dispatcher.addListener(() => notifyCount++);
    });

    tearDown(() {
      dispatcher.dispose();
    });

    test('add reflects in items and notifies exactly once', () {
      // Arrange — seed [1, 2] via mutate, then reset the counter.
      dispatcher.mutate((items) => items.addAll(<int>[1, 2]));
      notifyCount = 0;

      // Act
      dispatcher.mutate((items) => items.add(3));

      // Assert
      expect(dispatcher.items, equals(<int>[1, 2, 3]));
      expect(notifyCount, equals(1));
    });

    test('insert reflects in items and notifies once', () {
      // Arrange
      dispatcher.mutate((items) => items.addAll(<int>[1, 3]));
      notifyCount = 0;

      // Act
      dispatcher.mutate((items) => items.insert(1, 2));

      // Assert
      expect(dispatcher.items, equals(<int>[1, 2, 3]));
      expect(notifyCount, equals(1));
    });

    test('removeWhere reflects in items and notifies once', () {
      // Arrange
      dispatcher.mutate((items) => items.addAll(<int>[1, 2, 3]));
      notifyCount = 0;

      // Act
      dispatcher.mutate((items) => items.removeWhere((e) => e == 2));

      // Assert
      expect(dispatcher.items, equals(<int>[1, 3]));
      expect(notifyCount, equals(1));
    });

    test('clear empties items and notifies once', () {
      // Arrange
      dispatcher.mutate((items) => items.addAll(<int>[1, 2, 3]));
      notifyCount = 0;

      // Act
      dispatcher.mutate((items) => items.clear());

      // Assert
      expect(dispatcher.items, isEmpty);
      expect(notifyCount, equals(1));
    });

    test('index assignment ([]=) replaces the element and notifies once', () {
      // Arrange
      dispatcher.mutate((items) => items.addAll(<int>[1, 2]));
      notifyCount = 0;

      // Act
      dispatcher.mutate((items) => items[0] = 99);

      // Assert
      expect(dispatcher.items, equals(<int>[99, 2]));
      expect(notifyCount, equals(1));
    });

    test('compound operations in one callback notify exactly once (batching)',
        () {
      // Arrange — items == [1, 2, 3].
      dispatcher.mutate((items) => items.addAll(<int>[1, 2, 3]));
      notifyCount = 0;

      // Act — two operations inside a single mutate call.
      dispatcher.mutate((items) => items
        ..removeWhere((e) => e == 2)
        ..add(4));

      // Assert — single notification despite multiple operations.
      expect(dispatcher.items, equals(<int>[1, 3, 4]));
      expect(notifyCount, equals(1),
          reason: 'compound mutation must batch into a single notification');
    });

    test('empty callback still notifies exactly once', () {
      // Arrange
      dispatcher.mutate((items) => items.addAll(<int>[1, 2]));
      notifyCount = 0;

      // Act — a no-op callback.
      dispatcher.mutate((items) {});

      // Assert — mutate notifies unconditionally on success.
      expect(dispatcher.items, equals(<int>[1, 2]));
      expect(notifyCount, equals(1));
    });

    test('callback exception propagates and no notification is emitted', () {
      // Arrange
      dispatcher.mutate((items) => items.addAll(<int>[1, 2]));
      notifyCount = 0;

      // Act & Assert — the exception escapes mutate.
      expect(
        () => dispatcher.mutate((items) {
          items.add(3);
          throw StateError('boom');
        }),
        throwsStateError,
      );

      // Assert — partial change stays, notifyListeners was NOT called.
      expect(dispatcher.items, equals(<int>[1, 2, 3]),
          reason: 'partial changes are not rolled back');
      expect(notifyCount, equals(0),
          reason: 'no notification when the callback throws');
    });

    test('mutate does not change lastResult', () async {
      // Arrange — establish a lastResult via a real load.
      final loader = FakeLoader<_FakePage<int>>();
      final firstPage = _page(<int>[1, 2]);
      loader.enqueueValue(firstPage);
      await dispatcher.reload(
        params: const _TestParams(),
        load: loader.call,
      );
      expect(dispatcher.lastResult, same(firstPage));

      // Act
      dispatcher.mutate((items) => items.add(3));

      // Assert — a manual mutation is not a "load".
      expect(dispatcher.lastResult, same(firstPage));
    });

    test('mutate after dispose is a no-op: callback not invoked, no notify', () {
      // Arrange
      var called = false;
      dispatcher.dispose();

      // Act — mutate must be ignored after dispose.
      dispatcher.mutate((items) => called = true);

      // Assert
      expect(called, isFalse);
      expect(notifyCount, equals(0));
    });

    test('direct items.add throws UnsupportedError (read-side is unmodifiable)',
        () {
      // Arrange
      final view = dispatcher.items;

      // Act & Assert — the only sanctioned write path is mutate.
      expect(() => view.add(42), throwsUnsupportedError);
    });
  });

  // -------------------------------------------------------------------------
  // US2 — manual `hasMore` control via the setter (H-01).
  // -------------------------------------------------------------------------
  group('ACPageDispatcher — hasMore setter (US2, H-01)', () {
    late ACPageDispatcher<_TestParams, _FakePage<int>, int> dispatcher;
    late FakeLoader<_FakePage<int>> loader;

    setUp(() {
      dispatcher = _buildDispatcher();
      loader = FakeLoader<_FakePage<int>>();
    });

    tearDown(() {
      dispatcher.dispose();
    });

    test('setter updates the getter', () {
      // Arrange — fresh dispatcher reports hasMore=false.
      expect(dispatcher.hasMore, isFalse);

      // Act
      dispatcher.hasMore = true;

      // Assert
      expect(dispatcher.hasMore, isTrue);
    });

    test('setter does not notify listeners', () {
      // Arrange
      var notifyCount = 0;
      dispatcher.addListener(() => notifyCount++);

      // Act
      dispatcher.hasMore = false;
      dispatcher.hasMore = true;

      // Assert
      expect(notifyCount, equals(0),
          reason: 'changing hasMore must not notify subscribers');
    });

    test('hasMore=false makes loadMore a no-op (loader not invoked)', () async {
      // Arrange
      loader.enqueueValue(_page(<int>[1, 2]));
      dispatcher.hasMore = false;

      // Act
      await dispatcher.loadMore(
        params: const _TestParams(),
        load: loader.call,
      );

      // Assert
      expect(loader.callCount, equals(0),
          reason: 'loadMore must not run when hasMore=false');
      expect(dispatcher.items, isEmpty);
    });

    test('setting hasMore back to true re-enables loadMore', () async {
      // Arrange — disable then re-enable loadMore.
      loader.enqueueValue(_page(<int>[1, 2]));
      dispatcher.hasMore = false;
      dispatcher.hasMore = true;

      // Act
      await dispatcher.loadMore(
        params: const _TestParams(),
        load: loader.call,
      );

      // Assert
      expect(loader.callCount, equals(1));
      expect(dispatcher.items, equals(<int>[1, 2]));
    });
  });

  // -------------------------------------------------------------------------
  // US2 — interaction with reload / loadMore / active load.
  // -------------------------------------------------------------------------
  group('ACPageDispatcher — mutate/hasMore interaction (US2)', () {
    late ACPageDispatcher<_TestParams, _FakePage<int>, int> dispatcher;
    late FakeLoader<_FakePage<int>> loader;

    setUp(() {
      dispatcher = _buildDispatcher();
      loader = FakeLoader<_FakePage<int>>();
    });

    tearDown(() {
      dispatcher.dispose();
    });

    test('reload after mutate replaces the manually mutated list', () async {
      // Arrange — seed a manual item.
      dispatcher.mutate((items) => items.add(99));
      loader.enqueueValue(_page(<int>[1, 2]));

      // Act
      await dispatcher.reload(
        params: const _TestParams(),
        load: loader.call,
      );

      // Assert — reload replaces, manual edit is overwritten.
      expect(dispatcher.items, equals(<int>[1, 2]));
    });

    test('loadMore after mutate appends to the manually mutated list',
        () async {
      // Arrange — seed a manual item; enable loadMore (fresh default is false).
      dispatcher.mutate((items) => items.add(99));
      dispatcher.hasMore = true;
      loader.enqueueValue(_page(<int>[1]));

      // Act
      await dispatcher.loadMore(
        params: const _TestParams(),
        load: loader.call,
      );

      // Assert — loadMore appends after the manual item.
      expect(dispatcher.items, equals(<int>[99, 1]));
    });

    test('mutate/hasMore during an active load do not cancel it', () async {
      // Arrange — an in-flight reload blocked on a gate.
      final gate = Completer<_FakePage<int>>();
      Future<_FakePage<int>> slowLoad(_TestParams _) => gate.future;
      final future = dispatcher.reload(
        params: const _TestParams(),
        load: slowLoad,
      );
      expect(dispatcher.isLoading, isTrue);

      // Act — mutate and flip hasMore while the load is in flight.
      dispatcher.mutate((items) => items.add(99));
      dispatcher.hasMore = false;

      // Release the load and let it resolve.
      gate.complete(_page(<int>[1, 2]));
      await future;

      // Assert — the load was NOT cancelled: its result replaced the list.
      expect(dispatcher.items, equals(<int>[1, 2]),
          reason: 'the active load completes and overwrites manual edits');
      expect(dispatcher.isLoading, isFalse);
    });

    test('mutate and hasMore setter do not change lastResult', () async {
      // Arrange — establish a lastResult.
      final firstPage = _page(<int>[1, 2]);
      loader.enqueueValue(firstPage);
      await dispatcher.reload(
        params: const _TestParams(),
        load: loader.call,
      );
      expect(dispatcher.lastResult, same(firstPage));

      // Act
      dispatcher.mutate((items) => items.add(3));
      dispatcher.hasMore = false;

      // Assert
      expect(dispatcher.lastResult, same(firstPage));
    });
  });
}
