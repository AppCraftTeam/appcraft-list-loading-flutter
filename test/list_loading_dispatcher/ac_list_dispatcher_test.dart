// ignore_for_file: cascade_invocations, unused_element_parameter, prefer_const_constructors
import 'dart:async';

import 'package:appcraft_list_loading_flutter/src/ac_list_dispatcher.dart';
import 'package:appcraft_list_loading_flutter/src/ac_params.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_loader.dart';

/// Offset-based params — used by [ACListDispatcher] where the loader
/// returns a bare `List<T>` and `hasMore` is computed from `params.limit`.
final class _TestParams with ACParamsMixin, ACOffsetParamsMixin {
  const _TestParams({this.limit, this.offset, this.query});

  @override
  final int? limit;
  @override
  final int? offset;
  @override
  final String? query;
}

ACListDispatcher<_TestParams, int> _buildDispatcher() =>
    ACListDispatcher<_TestParams, int>();

void main() {
  group('ACListDispatcher — initial state (US1)', () {
    late ACListDispatcher<_TestParams, int> dispatcher;

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

    test('fresh dispatcher reports hasMore=true (parity, before first load)',
        () {
      // Arrange & Act & Assert
      expect(dispatcher.hasMore, isTrue);
    });

    test('is a ChangeNotifier / Listenable', () {
      // Arrange & Act & Assert
      expect(dispatcher, isA<ChangeNotifier>());
      expect(dispatcher, isA<Listenable>());
    });

    test('items getter returns an unmodifiable view', () {
      // Arrange
      final items = dispatcher.items;

      // Act & Assert
      expect(() => items.add(42), throwsUnsupportedError);
    });
  });

  group('ACListDispatcher — reload / loadMore (US1)', () {
    late ACListDispatcher<_TestParams, int> dispatcher;
    late FakeLoader<List<int>> loader;
    late int notifyCount;

    setUp(() {
      dispatcher = _buildDispatcher();
      loader = FakeLoader<List<int>>();
      notifyCount = 0;
      dispatcher.addListener(() => notifyCount++);
    });

    tearDown(() {
      dispatcher.dispose();
    });

    test('reload replaces items, sets isLoading during flight, notifies once',
        () async {
      // Arrange — limit=3 with a full page keeps hasMore=true.
      loader.enqueueValue(<int>[1, 2, 3]);

      // Act
      final future = dispatcher.reload(
        params: const _TestParams(limit: 3),
        load: loader.call,
      );
      // Between start and completion the dispatcher must be loading.
      expect(dispatcher.isLoading, isTrue);
      await future;

      // Assert
      expect(dispatcher.items, equals(<int>[1, 2, 3]));
      expect(dispatcher.hasMore, isTrue);
      expect(dispatcher.isLoading, isFalse);
      expect(dispatcher.lastResult, equals(<int>[1, 2, 3]));
      expect(loader.callCount, 1);
      expect(notifyCount, equals(1),
          reason: 'a successful reload must notify exactly once');
    });

    test('second reload replaces the accumulated items entirely', () async {
      // Arrange
      loader.enqueueValue(<int>[1, 2, 3]);
      loader.enqueueValue(<int>[7, 8]);
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
      expect(dispatcher.lastResult, equals(<int>[7, 8]));
    });

    test('loadMore appends items at the end and notifies once', () async {
      // Arrange — seed the list first.
      loader.enqueueValue(<int>[1, 2]);
      loader.enqueueValue(<int>[3, 4]);
      await dispatcher.reload(
        params: const _TestParams(),
        load: loader.call,
      );
      final countAfterReload = notifyCount;

      // Act
      await dispatcher.loadMore(
        params: const _TestParams(offset: 2),
        load: loader.call,
      );

      // Assert
      expect(dispatcher.items, equals(<int>[1, 2, 3, 4]));
      expect(dispatcher.lastResult, equals(<int>[3, 4]),
          reason: 'lastResult must point to the most recent page');
      expect(notifyCount - countAfterReload, equals(1));
      expect(loader.callCount, 2);
    });
  });

  group('ACListDispatcher — hasMore rule (US1)', () {
    late ACListDispatcher<_TestParams, int> dispatcher;
    late FakeLoader<List<int>> loader;

    setUp(() {
      dispatcher = _buildDispatcher();
      loader = FakeLoader<List<int>>();
    });

    tearDown(() {
      dispatcher.dispose();
    });

    test('limit == null: hasMore stays true regardless of page size', () async {
      // Arrange
      loader.enqueueValue(<int>[1]);

      // Act
      await dispatcher.reload(
        params: const _TestParams(),
        load: loader.call,
      );

      // Assert
      expect(dispatcher.hasMore, isTrue,
          reason: 'null limit means a source without an upper bound');
    });

    test('result.length == limit: hasMore=true (page is full)', () async {
      // Arrange
      loader.enqueueValue(<int>[1, 2, 3]);

      // Act
      await dispatcher.reload(
        params: const _TestParams(limit: 3),
        load: loader.call,
      );

      // Assert
      expect(dispatcher.hasMore, isTrue);
    });

    test('result.length < limit: hasMore=false (last page)', () async {
      // Arrange — limit=3 but only 1 element returned.
      loader.enqueueValue(<int>[42]);

      // Act
      await dispatcher.reload(
        params: const _TestParams(limit: 3),
        load: loader.call,
      );

      // Assert
      expect(dispatcher.items, equals(<int>[42]));
      expect(dispatcher.hasMore, isFalse);
    });

    test('loadMore with a short page flips hasMore to false', () async {
      // Arrange — limit=2 consistently; last page is a single element.
      loader.enqueueValue(<int>[1, 2]);
      loader.enqueueValue(<int>[3]);
      await dispatcher.reload(
        params: const _TestParams(limit: 2),
        load: loader.call,
      );
      expect(dispatcher.hasMore, isTrue);

      // Act
      await dispatcher.loadMore(
        params: const _TestParams(limit: 2, offset: 2),
        load: loader.call,
      );

      // Assert
      expect(dispatcher.items, equals(<int>[1, 2, 3]));
      expect(dispatcher.hasMore, isFalse);
    });
  });

  group('ACListDispatcher — loadMore guards (US1)', () {
    late ACListDispatcher<_TestParams, int> dispatcher;
    late FakeLoader<List<int>> loader;

    setUp(() {
      dispatcher = _buildDispatcher();
      loader = FakeLoader<List<int>>();
    });

    tearDown(() {
      dispatcher.dispose();
    });

    test('loadMore is a no-op when hasMore=false — loader not invoked',
        () async {
      // Arrange — seed hasMore=false (page shorter than limit).
      loader.enqueueValue(<int>[1]);
      await dispatcher.reload(
        params: const _TestParams(limit: 3),
        load: loader.call,
      );
      final callsBefore = loader.callCount;
      final itemsBefore = List<int>.from(dispatcher.items);
      var notifyAfter = 0;
      dispatcher.addListener(() => notifyAfter++);
      expect(dispatcher.hasMore, isFalse);

      // Act
      await dispatcher.loadMore(
        params: const _TestParams(limit: 3, offset: 1),
        load: loader.call,
      );

      // Assert
      expect(loader.callCount, equals(callsBefore),
          reason: 'loader must not run when hasMore=false');
      expect(dispatcher.items, equals(itemsBefore));
      expect(dispatcher.hasMore, isFalse);
      expect(notifyAfter, equals(0),
          reason: 'a no-op loadMore must not notify');
    });

    test('loadMore while another load is in flight is a no-op', () async {
      // Arrange — seed items + hasMore=true (no limit -> always more).
      loader.enqueueValue(<int>[1, 2]);
      await dispatcher.reload(
        params: const _TestParams(),
        load: loader.call,
      );
      // The first loadMore blocks on a gate.
      final gate = Completer<List<int>>();
      Future<List<int>> slowLoad(_TestParams _) => gate.future;
      final secondLoader = FakeLoader<List<int>>();
      secondLoader.enqueueValue(<int>[9, 9]);

      // Act — start one loadMore, then try a second concurrently.
      final firstFuture = dispatcher.loadMore(
        params: const _TestParams(offset: 2),
        load: slowLoad,
      );
      expect(dispatcher.isLoading, isTrue);
      await dispatcher.loadMore(
        params: const _TestParams(offset: 2),
        load: secondLoader.call,
      );

      // Release the first loadMore.
      gate.complete(<int>[3, 4]);
      await firstFuture;

      // Assert
      expect(secondLoader.callCount, 0,
          reason: 'concurrent loadMore must not invoke the second loader');
      expect(dispatcher.items, equals(<int>[1, 2, 3, 4]));
    });
  });
}
