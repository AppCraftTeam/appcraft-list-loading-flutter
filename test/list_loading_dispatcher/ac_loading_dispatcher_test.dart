// ignore_for_file: cascade_invocations, unused_element_parameter, prefer_const_constructors
import 'dart:async';

import 'package:appcraft_list_loading_flutter/src/ac_loading_dispatcher.dart';
import 'package:appcraft_list_loading_flutter/src/ac_params.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_loader.dart';

/// Minimal params for the extension-point tests. The base engine only reads
/// [query] (for the search strategy); [limit] is carried through to the
/// loader untouched.
final class _TestParams with ACParamsMixin {
  const _TestParams({this.limit, this.query});

  @override
  final int? limit;
  @override
  final String? query;
}

/// A minimal third-party subclass of [ACLoadingDispatcher] that accumulates
/// a `List<int>`.
///
/// Result type is `T = List<int>`: on success it replaces (reload) or appends
/// (loadMore) the incoming ints, derives a trivial `hasMore` rule
/// (`result.isNotEmpty`) and notifies. On a minLength rejection it clears the
/// collection and drops `hasMore`. It reuses the inherited loading engine
/// verbatim — no lifecycle logic of its own.
final class _IntAccumulatorDispatcher
    extends ACLoadingDispatcher<_TestParams, List<int>> {
  _IntAccumulatorDispatcher({super.searchStrategy});

  final List<int> _items = <int>[];
  bool _hasMore = true;

  /// Number of times [onLoadSuccess] fired — asserted by tests.
  int successCalls = 0;

  /// Number of times [onLoadRejected] fired — asserted by tests.
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

_IntAccumulatorDispatcher _buildDispatcher() => _IntAccumulatorDispatcher();

void main() {
  group('ACLoadingDispatcher (extension point) — reload (US3)', () {
    late _IntAccumulatorDispatcher dispatcher;
    late FakeLoader<List<int>> loader;

    setUp(() {
      dispatcher = _buildDispatcher();
      loader = FakeLoader<List<int>>();
    });

    tearDown(() {
      dispatcher.dispose();
    });

    test('reload_success_invokesOnLoadSuccessAndCommitsLastResult', () async {
      // Arrange
      final result = <int>[1, 2, 3];
      loader.enqueueValue(result);

      // Act — isLoading must flip true synchronously, before any await.
      final future = dispatcher.reload(
        params: const _TestParams(),
        load: loader.call,
      );
      final loadingRightAfterCall = dispatcher.isLoading;
      await future;

      // Assert
      expect(loadingRightAfterCall, isTrue,
          reason: 'isLoading is set synchronously by reload');
      expect(dispatcher.successCalls, equals(1));
      expect(dispatcher.items, equals(<int>[1, 2, 3]));
      expect(dispatcher.lastResult, same(result),
          reason: 'lastResult stores the exact loader result reference');
      expect(dispatcher.isLoading, isFalse,
          reason: 'isLoading is reset once the load completes');
    });
  });

  group('ACLoadingDispatcher (extension point) — loadMore guards (US3)', () {
    late _IntAccumulatorDispatcher dispatcher;
    late FakeLoader<List<int>> loader;

    setUp(() {
      dispatcher = _buildDispatcher();
      loader = FakeLoader<List<int>>();
    });

    tearDown(() {
      dispatcher.dispose();
    });

    test('loadMore_hasMoreFalse_isNoOp', () async {
      // Arrange — an empty result drives hasMore=false via the subclass rule.
      loader.enqueueValue(<int>[]);
      await dispatcher.reload(
        params: const _TestParams(),
        load: loader.call,
      );
      expect(dispatcher.hasMore, isFalse);
      final callsBefore = loader.callCount;

      // Act
      await dispatcher.loadMore(
        params: const _TestParams(),
        load: loader.call,
      );

      // Assert
      expect(loader.callCount, equals(callsBefore),
          reason: 'loader must not run when hasMore=false');
      expect(dispatcher.items, isEmpty);
    });

    test('loadMore_hasMoreTrue_appendsResult', () async {
      // Arrange — seed [1,2] with hasMore=true.
      loader.enqueueValue(<int>[1, 2]);
      loader.enqueueValue(<int>[3, 4]);
      await dispatcher.reload(
        params: const _TestParams(),
        load: loader.call,
      );
      expect(dispatcher.hasMore, isTrue);

      // Act
      await dispatcher.loadMore(
        params: const _TestParams(),
        load: loader.call,
      );

      // Assert
      expect(dispatcher.items, equals(<int>[1, 2, 3, 4]));
      expect(loader.callCount, equals(2));
    });

    test('loadMore_whileLoading_isNoOp', () async {
      // Arrange — seed items, hasMore=true.
      loader.enqueueValue(<int>[1, 2]);
      await dispatcher.reload(
        params: const _TestParams(),
        load: loader.call,
      );
      final gate = Completer<List<int>>();
      Future<List<int>> slowLoad(_TestParams _) => gate.future;
      final secondLoader = FakeLoader<List<int>>();
      secondLoader.enqueueValue(<int>[9, 9]);

      // Act — start a slow loadMore, then attempt a concurrent one.
      final firstFuture = dispatcher.loadMore(
        params: const _TestParams(),
        load: slowLoad,
      );
      expect(dispatcher.isLoading, isTrue);
      await dispatcher.loadMore(
        params: const _TestParams(),
        load: secondLoader.call,
      );
      gate.complete(<int>[3, 4]);
      await firstFuture;

      // Assert
      expect(secondLoader.callCount, equals(0),
          reason: 'a concurrent loadMore must not invoke its loader');
      expect(dispatcher.items, equals(<int>[1, 2, 3, 4]));
    });
  });

  group('ACLoadingDispatcher (extension point) — supersede & errors (US3)',
      () {
    test('reload_supersededByNewerReload_appliesOnlyLastResult', () async {
      // Arrange — the first loader blocks on a gate; its result must lose.
      final dispatcher = _buildDispatcher();
      final firstGate = Completer<List<int>>();
      Future<List<int>> firstLoad(_TestParams _) => firstGate.future;
      final secondLoader = FakeLoader<List<int>>();
      secondLoader.enqueueValue(<int>[9, 8, 7]);

      // Act — two back-to-back reloads; complete the first afterwards.
      final firstFuture = dispatcher.reload(
        params: const _TestParams(),
        load: firstLoad,
      );
      final secondFuture = dispatcher.reload(
        params: const _TestParams(),
        load: secondLoader.call,
      );
      firstGate.complete(<int>[1, 1, 1]);
      await Future.wait(<Future<void>>[firstFuture, secondFuture]);

      // Assert — only the second (latest) result lands.
      expect(dispatcher.items, equals(<int>[9, 8, 7]));
      expect(dispatcher.lastResult, equals(<int>[9, 8, 7]));
      expect(dispatcher.isLoading, isFalse);

      dispatcher.dispose();
    });

    test('reload_loaderThrows_rethrowsAndResetsIsLoading', () async {
      // Arrange
      final dispatcher = _buildDispatcher();
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

      // Assert
      expect(dispatcher.isLoading, isFalse,
          reason: 'isLoading must be reset via try/finally');
      expect(dispatcher.items, isEmpty);
      expect(dispatcher.lastResult, isNull);

      dispatcher.dispose();
    });
  });

  group('ACLoadingDispatcher (extension point) — dispose (US3)', () {
    test('dispose_clearsLastResultAndMakesSubsequentCallsNoOps', () async {
      // Arrange — seed a successful load first.
      final dispatcher = _buildDispatcher();
      final loader = FakeLoader<List<int>>();
      loader.enqueueValue(<int>[1, 2]);
      await dispatcher.reload(
        params: const _TestParams(),
        load: loader.call,
      );
      expect(dispatcher.lastResult, isNotNull);

      // Act
      dispatcher.dispose();

      // Assert — lastResult is cleared by dispose.
      expect(dispatcher.lastResult, isNull);

      // Subsequent reload/loadMore are no-ops (loader never invoked).
      final afterLoader = FakeLoader<List<int>>();
      afterLoader.enqueueValue(<int>[3, 4]);
      await dispatcher.reload(
        params: const _TestParams(),
        load: afterLoader.call,
      );
      await dispatcher.loadMore(
        params: const _TestParams(),
        load: afterLoader.call,
      );
      expect(afterLoader.callCount, equals(0),
          reason: 'no loader may run after dispose');
    });

    test('dispose_isIdempotent', () {
      // Arrange
      final dispatcher = _buildDispatcher();

      // Act & Assert
      dispatcher.dispose();
      expect(dispatcher.dispose, returnsNormally);
    });

    test('dispatcher_isChangeNotifier', () {
      // Arrange
      final dispatcher = _buildDispatcher();

      // Act & Assert
      expect(dispatcher, isA<ChangeNotifier>());
      expect(dispatcher, isA<Listenable>());

      dispatcher.dispose();
    });
  });
}
