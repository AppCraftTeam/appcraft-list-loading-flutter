// ignore_for_file: cascade_invocations, unused_element_parameter, prefer_const_constructors
import 'package:appcraft_list_loading_flutter/src/ac_list_dispatcher.dart';
import 'package:appcraft_list_loading_flutter/src/ac_params.dart';
import 'package:appcraft_list_loading_flutter/src/ac_search_debouncer.dart';
import 'package:appcraft_list_loading_flutter/src/ac_search_strategy.dart';
import 'package:fake_async/fake_async.dart';
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

ACListDispatcher<_TestParams, int> _buildDispatcher({
  ACSearchStrategy? searchStrategy,
}) =>
    ACListDispatcher<_TestParams, int>(
      searchStrategy: searchStrategy,
    );

void main() {
  group('ACListDispatcher — default search strategy (US2)', () {
    test('default strategy is ACSearchDebouncer (minLength 3)', () {
      // Arrange & Act
      final dispatcher = _buildDispatcher();

      // Assert
      final strategy = dispatcher.searchStrategy;
      expect(strategy, isA<ACSearchDebouncer>());
      final debounced = strategy as ACSearchDebouncer;
      expect(debounced.minLength, equals(3));

      dispatcher.dispose();
    });

    test('custom strategy passed to the constructor is used verbatim', () {
      // Arrange
      final custom = ACSearchDebouncer(
        debounce: const Duration(milliseconds: 50),
        minLength: 1,
      );

      // Act
      final dispatcher = _buildDispatcher(searchStrategy: custom);

      // Assert
      expect(dispatcher.searchStrategy, same(custom));

      dispatcher.dispose();
    });
  });

  group('ACListDispatcher — search in reload (US2)', () {
    test('query == null: load starts immediately, no debounce delay', () {
      FakeAsync().run((async) {
        // Arrange
        final dispatcher = _buildDispatcher();
        final loader = FakeLoader<List<int>>();
        loader.enqueueValue(<int>[1, 2, 3]);

        // Act — fire-and-forget; FakeAsync runs the future synchronously.
        dispatcher
            .reload(
              params: const _TestParams(),
              load: loader.call,
            )
            .ignore();
        async.flushMicrotasks();

        // Assert — loader was invoked without any fake-time elapsing.
        expect(loader.callCount, 1,
            reason: 'null query must trigger an immediate load');
        expect(dispatcher.items, equals(<int>[1, 2, 3]));
        expect(dispatcher.isLoading, isFalse);

        dispatcher.dispose();
      });
    });

    test('query == "" (empty string) behaves like null: immediate load', () {
      FakeAsync().run((async) {
        // Arrange
        final dispatcher = _buildDispatcher();
        final loader = FakeLoader<List<int>>();
        loader.enqueueValue(<int>[10, 20]);

        // Act
        dispatcher
            .reload(
              params: const _TestParams(query: ''),
              load: loader.call,
            )
            .ignore();
        async.flushMicrotasks();

        // Assert
        expect(loader.callCount, 1);
        expect(dispatcher.items, equals(<int>[10, 20]));

        dispatcher.dispose();
      });
    });

    test(
        'query.length < minLength: items cleared, hasMore=false, loader NOT '
        'called, lastResult preserved', () {
      FakeAsync().run((async) {
        // Arrange — seed items so we can observe clearing.
        final dispatcher = _buildDispatcher();
        final seedLoader = FakeLoader<List<int>>();
        final firstPage = <int>[1, 2, 3];
        seedLoader.enqueueValue(firstPage);
        dispatcher
            .reload(
              params: const _TestParams(),
              load: seedLoader.call,
            )
            .ignore();
        async.flushMicrotasks();
        expect(dispatcher.items, equals(<int>[1, 2, 3]));
        expect(dispatcher.lastResult, same(firstPage));

        // Act — reload with a too-short query.
        final searchLoader = FakeLoader<List<int>>();
        dispatcher
            .reload(
              params: const _TestParams(query: 'ab'),
              load: searchLoader.call,
            )
            .ignore();
        async.elapse(const Duration(seconds: 1));
        async.flushMicrotasks();

        // Assert
        expect(searchLoader.callCount, 0,
            reason: 'loader must not run when query is shorter than minLength');
        expect(dispatcher.items, isEmpty,
            reason: 'short-query reload must clear accumulated items');
        expect(dispatcher.hasMore, isFalse);
        expect(dispatcher.isLoading, isFalse);
        expect(dispatcher.lastResult, same(firstPage),
            reason: 'minLength rejection must not reset lastResult');

        dispatcher.dispose();
      });
    });

    test(
        'minLength rejection on an already-empty list: no notification',
        () {
      FakeAsync().run((async) {
        // Arrange — items are empty right after construction.
        final dispatcher = _buildDispatcher();
        final loader = FakeLoader<List<int>>();
        var notifyCount = 0;
        dispatcher.addListener(() => notifyCount++);

        // Act — short query, items stay empty (no change).
        dispatcher
            .reload(
              params: const _TestParams(query: 'ab'),
              load: loader.call,
            )
            .ignore();
        async.flushMicrotasks();

        // Assert
        expect(dispatcher.items, isEmpty);
        expect(notifyCount, equals(0),
            reason: 'no items change means no notification');

        dispatcher.dispose();
      });
    });

    test('changed query with length >= minLength: debounce delays the load',
        () {
      FakeAsync().run((async) {
        // Arrange
        final dispatcher = _buildDispatcher();
        final loader = FakeLoader<List<int>>();
        loader.enqueueValue(<int>[100, 200, 300]);

        // Act — schedule a search; nothing should run before debounce.
        dispatcher
            .reload(
              params: const _TestParams(query: 'john'),
              load: loader.call,
            )
            .ignore();
        async.elapse(const Duration(milliseconds: 100));
        async.flushMicrotasks();

        // Assert — debounce has not expired yet.
        expect(loader.callCount, 0,
            reason: 'loader must not fire before debounce elapses');
        expect(dispatcher.items, isEmpty);

        // Act — advance past the remaining debounce (300ms total).
        async.elapse(const Duration(milliseconds: 300));
        async.flushMicrotasks();

        // Assert — loader fired once, items updated.
        expect(loader.callCount, 1);
        expect(dispatcher.items, equals(<int>[100, 200, 300]));
        expect(dispatcher.isLoading, isFalse);

        dispatcher.dispose();
      });
    });

    test(
        'two successive reloads within debounce window: first timer cancelled, '
        'second query wins', () {
      FakeAsync().run((async) {
        // Arrange
        final dispatcher = _buildDispatcher();
        final loader = FakeLoader<List<int>>();
        loader.enqueueValue(<int>[7, 8]);

        // Act — first reload starts the debounce timer.
        dispatcher
            .reload(
              params: const _TestParams(query: 'joh'),
              load: loader.call,
            )
            .ignore();
        async.elapse(const Duration(milliseconds: 100));

        // Second reload with a different query, still within debounce window.
        dispatcher
            .reload(
              params: const _TestParams(query: 'john'),
              load: loader.call,
            )
            .ignore();
        async.elapse(const Duration(milliseconds: 100));
        async.flushMicrotasks();

        // Assert — neither query has fired yet.
        expect(loader.callCount, 0);

        // Act — elapse the rest of the second reload's debounce.
        async.elapse(const Duration(milliseconds: 300));
        async.flushMicrotasks();

        // Assert — only the second query triggered the loader exactly once.
        expect(loader.callCount, 1);
        final lastParams = loader.calls.single as _TestParams;
        expect(lastParams.query, equals('john'),
            reason: 'loader must receive the last-requested query');
        expect(dispatcher.items, equals(<int>[7, 8]));

        dispatcher.dispose();
      });
    });

    test(
        'repeated reload with the same applied query: load starts immediately '
        '(no debounce)', () {
      FakeAsync().run((async) {
        // Arrange — first, apply the query normally through debounce.
        final dispatcher = _buildDispatcher();
        final loader = FakeLoader<List<int>>();
        loader.enqueueValue(<int>[1, 2]);
        loader.enqueueValue(<int>[3, 4]);
        dispatcher
            .reload(
              params: const _TestParams(query: 'john'),
              load: loader.call,
            )
            .ignore();
        async.elapse(const Duration(milliseconds: 300));
        async.flushMicrotasks();
        expect(loader.callCount, 1, reason: 'first search debounced then ran');

        // Act — repeat the same query.
        dispatcher
            .reload(
              params: const _TestParams(query: 'john'),
              load: loader.call,
            )
            .ignore();
        async.flushMicrotasks();

        // Assert — loader was called a second time without any elapse.
        expect(loader.callCount, 2,
            reason: 'repeated query must bypass debounce');
        expect(dispatcher.items, equals(<int>[3, 4]));

        dispatcher.dispose();
      });
    });

    test('custom minLength=1 strategy: single-char query passes and loads', () {
      FakeAsync().run((async) {
        // Arrange — custom strategy with zero debounce, minLength 1.
        final dispatcher = _buildDispatcher(
          searchStrategy: ACSearchDebouncer(
            debounce: Duration.zero,
            minLength: 1,
          ),
        );
        final loader = FakeLoader<List<int>>();
        loader.enqueueValue(<int>[5, 6]);

        // Act
        dispatcher
            .reload(
              params: const _TestParams(query: 'a'),
              load: loader.call,
            )
            .ignore();
        async.flushMicrotasks();

        // Assert — 1-char query satisfies the custom minLength.
        expect(loader.callCount, 1);
        expect(dispatcher.items, equals(<int>[5, 6]));

        dispatcher.dispose();
      });
    });
  });

  group('ACListDispatcher — loadMore search semantics (US2)', () {
    test('loadMore with any query does NOT apply debounce: loader runs now',
        () {
      FakeAsync().run((async) {
        // Arrange — seed items with a normal reload first.
        final dispatcher = _buildDispatcher();
        final loader = FakeLoader<List<int>>()
          ..enqueueValue(<int>[1, 2])
          ..enqueueValue(<int>[3, 4]);
        dispatcher
            .reload(
              params: const _TestParams(),
              load: loader.call,
            )
            .ignore();
        async.flushMicrotasks();
        expect(loader.callCount, 1);
        expect(dispatcher.hasMore, isTrue);

        // Act — loadMore with a query, without advancing fake time.
        dispatcher
            .loadMore(
              params: const _TestParams(offset: 2, query: 'abc'),
              load: loader.call,
            )
            .ignore();
        async.flushMicrotasks();

        // Assert — loader was called a second time immediately, no debounce.
        expect(loader.callCount, 2,
            reason: 'loadMore must not apply debounce');
        expect(dispatcher.items, equals(<int>[1, 2, 3, 4]));

        dispatcher.dispose();
      });
    });

    test(
        'loadMore with a query shorter than minLength: minLength check does '
        'NOT apply; loader fires normally', () {
      FakeAsync().run((async) {
        // Arrange
        final dispatcher = _buildDispatcher();
        final loader = FakeLoader<List<int>>()
          ..enqueueValue(<int>[1, 2])
          ..enqueueValue(<int>[3, 4]);
        dispatcher
            .reload(
              params: const _TestParams(),
              load: loader.call,
            )
            .ignore();
        async.flushMicrotasks();
        expect(dispatcher.hasMore, isTrue);

        // Act — loadMore with a 2-char query (minLength default = 3).
        dispatcher
            .loadMore(
              params: const _TestParams(offset: 2, query: 'ab'),
              load: loader.call,
            )
            .ignore();
        async.flushMicrotasks();

        // Assert
        expect(loader.callCount, 2);
        expect(dispatcher.items, equals(<int>[1, 2, 3, 4]));
        expect(dispatcher.hasMore, isTrue);

        dispatcher.dispose();
      });
    });

    test(
        'loadMore does NOT mutate last-applied query: a later reload with the '
        'original query still skips debounce', () {
      FakeAsync().run((async) {
        // Arrange — apply 'john' through debounce.
        final dispatcher = _buildDispatcher();
        final loader = FakeLoader<List<int>>()
          ..enqueueValue(<int>[1, 2])
          ..enqueueValue(<int>[3, 4])
          ..enqueueValue(<int>[5, 6]);
        dispatcher
            .reload(
              params: const _TestParams(query: 'john'),
              load: loader.call,
            )
            .ignore();
        async.elapse(const Duration(milliseconds: 300));
        async.flushMicrotasks();
        expect(loader.callCount, 1);

        // Act 1 — loadMore with a DIFFERENT query; must not change
        // last-applied inside the search strategy.
        dispatcher
            .loadMore(
              params: const _TestParams(offset: 2, query: 'different'),
              load: loader.call,
            )
            .ignore();
        async.flushMicrotasks();
        expect(loader.callCount, 2);

        // Act 2 — reload with original 'john'. If loadMore had overwritten
        // last-applied to 'different', this reload would be debounced.
        dispatcher
            .reload(
              params: const _TestParams(query: 'john'),
              load: loader.call,
            )
            .ignore();
        async.flushMicrotasks();

        // Assert
        expect(loader.callCount, 3,
            reason: 'loadMore must not mutate last-applied query');
        expect(dispatcher.items, equals(<int>[5, 6]));

        dispatcher.dispose();
      });
    });
  });
}
