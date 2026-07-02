// ignore_for_file: cascade_invocations, unused_element_parameter, prefer_const_constructors
import 'dart:async';

import 'package:appcraft_list_loading_flutter/src/ac_cancel_strategy.dart';
import 'package:appcraft_list_loading_flutter/src/ac_list_dispatcher.dart';
import 'package:appcraft_list_loading_flutter/src/ac_params.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_loader.dart';

/// Offset-based params used with [ACListDispatcher].
final class _TestParams with ACParamsMixin, ACOffsetParamsMixin {
  const _TestParams({this.limit, this.offset, this.query});

  @override
  final int? limit;
  @override
  final int? offset;
  @override
  final String? query;
}

/// Spy [ACCancelStrategy] used to verify which strategy the dispatcher picks
/// per call.
///
/// Delegates the actual cancellation semantics to an internal
/// [ACOperationCancelStrategy] so dispatcher interactions stay realistic
/// (awaited futures still resolve through `valueOrCancellation`). Tracks the
/// number of `run`/`cancel` invocations.
final class _SpyCancelStrategy implements ACCancelStrategy {
  _SpyCancelStrategy();

  int runCalls = 0;
  int cancelCalls = 0;
  final ACOperationCancelStrategy _inner = ACOperationCancelStrategy();

  @override
  Future<T?> run<T>(Future<T> future) {
    runCalls++;
    return _inner.run<T>(future);
  }

  @override
  Future<void> cancel() async {
    cancelCalls++;
    await _inner.cancel();
  }

  @override
  bool get isActive => _inner.isActive;
}

ACListDispatcher<_TestParams, int> _buildDispatcher() =>
    ACListDispatcher<_TestParams, int>();

void main() {
  group('ACListDispatcher — reload supersedes an in-flight load (US2)', () {
    test('a newer reload cancels the prior one: only the second result lands',
        () async {
      // Arrange — the first loader blocks on a completer; its result must be
      // discarded in favour of the second reload.
      final dispatcher = _buildDispatcher();
      final firstGate = Completer<List<int>>();
      Future<List<int>> firstLoad(_TestParams _) => firstGate.future;
      final secondLoader = FakeLoader<List<int>>();
      secondLoader.enqueueValue(<int>[9, 8, 7]);

      // Act
      final firstFuture = dispatcher.reload(
        params: const _TestParams(),
        load: firstLoad,
      );
      final secondFuture = dispatcher.reload(
        params: const _TestParams(),
        load: secondLoader.call,
      );
      // Let the first loader finally resolve — result must be ignored.
      firstGate.complete(<int>[1, 1, 1]);
      await Future.wait(<Future<void>>[firstFuture, secondFuture]);

      // Assert
      expect(dispatcher.items, equals(<int>[9, 8, 7]));
      expect(dispatcher.isLoading, isFalse);

      dispatcher.dispose();
    });

    test('reload cancels an in-flight loadMore: only reload result stands',
        () async {
      // Arrange — seed non-empty items.
      final dispatcher = _buildDispatcher();
      final loader = FakeLoader<List<int>>();
      loader.enqueueValue(<int>[1, 2]);
      await dispatcher.reload(
        params: const _TestParams(),
        load: loader.call,
      );
      // Start a slow loadMore.
      final loadMoreGate = Completer<List<int>>();
      Future<List<int>> slowLoadMore(_TestParams _) => loadMoreGate.future;
      final reloadLoader = FakeLoader<List<int>>();
      reloadLoader.enqueueValue(<int>[100, 200]);

      // Act
      final loadMoreFuture = dispatcher.loadMore(
        params: const _TestParams(offset: 2),
        load: slowLoadMore,
      );
      final reloadFuture = dispatcher.reload(
        params: const _TestParams(),
        load: reloadLoader.call,
      );
      loadMoreGate.complete(<int>[3, 4]);
      await Future.wait(<Future<void>>[loadMoreFuture, reloadFuture]);

      // Assert — reload replaces items; loadMore result is discarded.
      expect(dispatcher.items, equals(<int>[100, 200]));
      expect(dispatcher.isLoading, isFalse);

      dispatcher.dispose();
    });
  });

  group('ACListDispatcher — cancel() (US2)', () {
    test('cancel() with no active load is a safe no-op', () async {
      // Arrange
      final dispatcher = _buildDispatcher();
      final itemsBefore = List<int>.from(dispatcher.items);
      final hasMoreBefore = dispatcher.hasMore;

      // Act & Assert
      await expectLater(dispatcher.cancel(), completes);
      expect(dispatcher.isLoading, isFalse);
      expect(dispatcher.items, equals(itemsBefore));
      expect(dispatcher.hasMore, equals(hasMoreBefore));

      dispatcher.dispose();
    });

    test(
        'cancel() with an active load: isLoading reset, items and hasMore '
        'and lastResult preserved, pending result ignored, no notification',
        () async {
      // Arrange — seed a known list first.
      final dispatcher = _buildDispatcher();
      final seedLoader = FakeLoader<List<int>>();
      final firstPage = <int>[1, 2];
      seedLoader.enqueueValue(firstPage);
      await dispatcher.reload(
        params: const _TestParams(),
        load: seedLoader.call,
      );
      final itemsBefore = List<int>.from(dispatcher.items);
      final hasMoreBefore = dispatcher.hasMore;
      var notifyAfterSeed = 0;
      dispatcher.addListener(() => notifyAfterSeed++);
      // Start a loadMore that will be cancelled before completion.
      final gate = Completer<List<int>>();
      Future<List<int>> gatedLoad(_TestParams _) => gate.future;

      // Act
      final loadMoreFuture = dispatcher.loadMore(
        params: const _TestParams(offset: 2),
        load: gatedLoad,
      );
      expect(dispatcher.isLoading, isTrue);
      await dispatcher.cancel();
      // Complete the loader after cancel — result must be ignored.
      gate.complete(<int>[9, 9, 9]);
      try {
        await loadMoreFuture;
      } on Object catch (_) {
        // Completing after cancel may or may not propagate; either is fine.
      }

      // Assert
      expect(dispatcher.isLoading, isFalse);
      expect(dispatcher.items, equals(itemsBefore));
      expect(dispatcher.hasMore, equals(hasMoreBefore));
      expect(dispatcher.lastResult, same(firstPage),
          reason: 'cancel must not overwrite lastResult with the late result');
      expect(notifyAfterSeed, equals(0),
          reason: 'cancel does not change items, so it must not notify');

      dispatcher.dispose();
    });
  });

  group('ACListDispatcher — per-call cancelStrategy (US2)', () {
    test('reload with per-call cancelStrategy uses the supplied strategy',
        () async {
      // Arrange
      final dispatcher = _buildDispatcher();
      final spy = _SpyCancelStrategy();
      final loader = FakeLoader<List<int>>();
      loader.enqueueValue(<int>[1, 2, 3]);

      // Act
      await dispatcher.reload(
        params: const _TestParams(),
        load: loader.call,
        cancelStrategy: spy,
      );

      // Assert — the override was consulted and the load completed through it.
      expect(spy.runCalls, equals(1),
          reason: 'override strategy must wrap the loader Future once');
      expect(dispatcher.items, equals(<int>[1, 2, 3]));
      expect(dispatcher.isLoading, isFalse);

      dispatcher.dispose();
    });

    test('loadMore with per-call cancelStrategy uses the supplied strategy',
        () async {
      // Arrange — seed the dispatcher so hasMore stays true.
      final dispatcher = _buildDispatcher();
      final seedLoader = FakeLoader<List<int>>();
      seedLoader.enqueueValue(<int>[1, 2]);
      await dispatcher.reload(
        params: const _TestParams(),
        load: seedLoader.call,
      );
      expect(dispatcher.hasMore, isTrue);

      final spy = _SpyCancelStrategy();
      final loadMoreLoader = FakeLoader<List<int>>();
      loadMoreLoader.enqueueValue(<int>[3, 4]);

      // Act
      await dispatcher.loadMore(
        params: const _TestParams(offset: 2),
        load: loadMoreLoader.call,
        cancelStrategy: spy,
      );

      // Assert
      expect(spy.runCalls, equals(1),
          reason: 'loadMore must honour the per-call override');
      expect(dispatcher.items, equals(<int>[1, 2, 3, 4]));

      dispatcher.dispose();
    });

    test(
        'without an override each call spins up a fresh strategy: the second '
        'reload cancels the first', () async {
      // Arrange — no override. Dispatcher must internally create a new
      // ACOperationCancelStrategy per call.
      final dispatcher = _buildDispatcher();
      final firstGate = Completer<List<int>>();
      Future<List<int>> firstLoad(_TestParams _) => firstGate.future;
      final secondLoader = FakeLoader<List<int>>();
      secondLoader.enqueueValue(<int>[5, 6]);

      // Act — two back-to-back reloads; the first one blocks on a completer.
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

      // Assert — only the second result lands.
      expect(dispatcher.items, equals(<int>[5, 6]));
      expect(dispatcher.isLoading, isFalse);

      dispatcher.dispose();
    });

    test('per-call override does NOT leak into a subsequent reload',
        () async {
      // Arrange
      final dispatcher = _buildDispatcher();
      final firstSpy = _SpyCancelStrategy();
      final loader = FakeLoader<List<int>>()
        ..enqueueValue(<int>[1, 2])
        ..enqueueValue(<int>[3, 4]);

      // Act — first reload with override; second reload without.
      await dispatcher.reload(
        params: const _TestParams(),
        load: loader.call,
        cancelStrategy: firstSpy,
      );
      await dispatcher.reload(
        params: const _TestParams(),
        load: loader.call,
      );

      // Assert — override was used only once.
      expect(firstSpy.runCalls, equals(1),
          reason: 'override is per-call, not persistent');
      expect(dispatcher.items, equals(<int>[3, 4]));

      dispatcher.dispose();
    });
  });

  group('ACListDispatcher — loader errors (US2)', () {
    late ACListDispatcher<_TestParams, int> dispatcher;
    late FakeLoader<List<int>> loader;

    setUp(() {
      dispatcher = _buildDispatcher();
      loader = FakeLoader<List<int>>();
    });

    tearDown(() {
      dispatcher.dispose();
    });

    test('reload rethrows loader exceptions; items empty, isLoading reset',
        () async {
      // Arrange
      final failure = Exception('network down');
      loader.enqueueError(failure);

      // Act & Assert — reload must propagate the error to the caller.
      await expectLater(
        dispatcher.reload(
          params: const _TestParams(),
          load: loader.call,
        ),
        throwsA(same(failure)),
      );

      // Assert
      expect(dispatcher.items, isEmpty);
      expect(dispatcher.isLoading, isFalse,
          reason: 'isLoading must be reset via try/finally');
      expect(dispatcher.lastResult, isNull);
    });

    test(
        'reload error on a populated list preserves items and lastResult',
        () async {
      // Arrange — first successful reload seeds items.
      final firstPage = <int>[1, 2, 3];
      loader.enqueueValue(firstPage);
      await dispatcher.reload(
        params: const _TestParams(),
        load: loader.call,
      );
      // Next call fails.
      final failure = StateError('boom');
      loader.enqueueError(failure);

      // Act & Assert — reload throws.
      await expectLater(
        dispatcher.reload(
          params: const _TestParams(),
          load: loader.call,
        ),
        throwsA(same(failure)),
      );

      // Assert — previous state stays.
      expect(dispatcher.items, equals(<int>[1, 2, 3]));
      expect(dispatcher.isLoading, isFalse);
      expect(dispatcher.lastResult, same(firstPage),
          reason: 'a failed reload must not overwrite lastResult');
    });

    test('loadMore rethrows; previous items and hasMore are preserved',
        () async {
      // Arrange — seed a two-item list (hasMore=true via null limit).
      loader.enqueueValue(<int>[1, 2]);
      await dispatcher.reload(
        params: const _TestParams(),
        load: loader.call,
      );
      final itemsBefore = List<int>.from(dispatcher.items);
      final hasMoreBefore = dispatcher.hasMore;
      // Next loadMore fails.
      final failure = Exception('load more failed');
      loader.enqueueError(failure);

      // Act & Assert
      await expectLater(
        dispatcher.loadMore(
          params: const _TestParams(offset: 2),
          load: loader.call,
        ),
        throwsA(same(failure)),
      );

      // Assert
      expect(dispatcher.items, equals(itemsBefore));
      expect(dispatcher.hasMore, equals(hasMoreBefore));
      expect(dispatcher.isLoading, isFalse);
    });

    test('a subsequent successful reload replaces items after an error',
        () async {
      // Arrange — first fail.
      final failure = Exception('first fail');
      loader.enqueueError(failure);
      await expectLater(
        dispatcher.reload(
          params: const _TestParams(),
          load: loader.call,
        ),
        throwsA(same(failure)),
      );

      // Then succeed.
      loader.enqueueValue(<int>[7, 8, 9]);

      // Act
      await dispatcher.reload(
        params: const _TestParams(),
        load: loader.call,
      );

      // Assert
      expect(dispatcher.items, equals(<int>[7, 8, 9]));
      expect(dispatcher.isLoading, isFalse);
    });
  });

  group('ACListDispatcher — notify semantics (US2)', () {
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

    test('loader error does NOT trigger notifyListeners (items unchanged)',
        () async {
      // Arrange
      final failure = Exception('boom');
      loader.enqueueError(failure);

      // Act & Assert — the thrown error is expected.
      await expectLater(
        dispatcher.reload(
          params: const _TestParams(),
          load: loader.call,
        ),
        throwsA(same(failure)),
      );

      // Assert — no notification because items never changed.
      expect(notifyCount, equals(0),
          reason: 'notifyListeners only fires when items actually change');
    });

    test(
        'isLoading transition alone does not fire a notification',
        () async {
      // Arrange — a gated loader keeps isLoading=true for a while.
      final gate = Completer<List<int>>();
      Future<List<int>> slow(_TestParams _) => gate.future;

      // Act — kick off the reload but DO NOT await.
      final future = dispatcher.reload(
        params: const _TestParams(),
        load: slow,
      );
      await Future<void>.delayed(Duration.zero);

      // Assert — no notification yet, because items haven't changed.
      expect(dispatcher.isLoading, isTrue);
      expect(notifyCount, equals(0),
          reason: 'isLoading transition alone must not notify');

      // Cleanup — let the loader finish so tearDown can dispose cleanly.
      gate.complete(<int>[1, 2]);
      await future;
      expect(notifyCount, equals(1),
          reason: 'the terminal items change fires exactly one notification');
    });
  });

  group('ACListDispatcher — dispose & stale results (US2)', () {
    test(
        'dispose() while a reload is in flight: pending result discarded, no '
        'notifications after dispose, lastResult null', () async {
      // Arrange
      final dispatcher = _buildDispatcher();
      var notifyCount = 0;
      dispatcher.addListener(() => notifyCount++);
      final gate = Completer<List<int>>();
      Future<List<int>> gatedLoad(_TestParams _) => gate.future;

      // Act
      final reloadFuture = dispatcher.reload(
        params: const _TestParams(),
        load: gatedLoad,
      );
      dispatcher.dispose();
      final countAfterDispose = notifyCount;
      gate.complete(<int>[1, 2, 3]);
      try {
        await reloadFuture;
      } on Object catch (_) {
        // Cancellation-after-dispose is silent; swallow any late result.
      }

      // Assert
      expect(notifyCount, equals(countAfterDispose),
          reason: 'dispatcher must not notify after dispose');
      expect(dispatcher.items, isEmpty,
          reason: 'late loader result must not mutate items after dispose');
      expect(dispatcher.lastResult, isNull,
          reason: 'dispose must clear lastResult');
    });

    test('dispose() clears a previously loaded lastResult', () async {
      // Arrange
      final dispatcher = _buildDispatcher();
      final loader = FakeLoader<List<int>>();
      final firstPage = <int>[1, 2, 3];
      loader.enqueueValue(firstPage);
      await dispatcher.reload(
        params: const _TestParams(),
        load: loader.call,
      );
      expect(dispatcher.lastResult, same(firstPage));

      // Act
      dispatcher.dispose();

      // Assert
      expect(dispatcher.lastResult, isNull);
    });

    test('repeated dispose() is idempotent (does not throw)', () {
      // Arrange
      final dispatcher = _buildDispatcher();

      // Act & Assert
      dispatcher.dispose();
      expect(dispatcher.dispose, returnsNormally);
    });

    test('public methods after dispose are no-ops (loader not invoked)',
        () async {
      // Arrange
      final dispatcher = _buildDispatcher();
      dispatcher.dispose();
      final loader = FakeLoader<List<int>>();
      loader.enqueueValue(<int>[1, 2, 3]);

      // Act — reload and loadMore after dispose must do nothing.
      await dispatcher.reload(
        params: const _TestParams(),
        load: loader.call,
      );
      await dispatcher.loadMore(
        params: const _TestParams(),
        load: loader.call,
      );

      // Assert
      expect(loader.callCount, 0,
          reason: 'no loader call may happen after dispose');
      expect(dispatcher.items, isEmpty);
    });

    test('addListener after dispose throws FlutterError (ChangeNotifier)', () {
      // Arrange
      final dispatcher = _buildDispatcher();
      dispatcher.dispose();

      // Act & Assert
      expect(
        () => dispatcher.addListener(() {}),
        throwsA(isA<FlutterError>()),
      );
    });
  });
}
