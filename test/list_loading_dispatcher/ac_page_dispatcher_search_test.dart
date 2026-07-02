// ignore_for_file: cascade_invocations, unused_element_parameter, prefer_const_constructors
import 'package:appcraft_list_loading_flutter/src/ac_page.dart';
import 'package:appcraft_list_loading_flutter/src/ac_page_dispatcher.dart';
import 'package:appcraft_list_loading_flutter/src/ac_params.dart';
import 'package:appcraft_list_loading_flutter/src/ac_search_strategy.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_loader.dart';

/// Params for the DTO scenario — only [query] drives search behaviour.
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

ACPageDispatcher<_TestParams, _FakePage<int>, int> _buildDispatcher({
  ACSearchStrategy? searchStrategy,
}) =>
    ACPageDispatcher<_TestParams, _FakePage<int>, int>(
      searchStrategy: searchStrategy,
    );

void main() {
  group('ACPageDispatcher — default search strategy (US2, D-11)', () {
    test('default strategy is ACDebouncedSearchStrategy (300ms / minLength 3)',
        () {
      // Arrange & Act
      final dispatcher = _buildDispatcher();

      // Assert
      final strategy = dispatcher.searchStrategy;
      expect(strategy, isA<ACDebouncedSearchStrategy>());
      final debounced = strategy as ACDebouncedSearchStrategy;
      expect(debounced.debounce, equals(const Duration(milliseconds: 300)));
      expect(debounced.minLength, equals(3));

      dispatcher.dispose();
    });

    test('custom strategy passed to the constructor is used verbatim', () {
      // Arrange
      final custom = ACDebouncedSearchStrategy(
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

  group('ACPageDispatcher — search in reload (US2, D-04)', () {
    test('query == null: load starts immediately, no debounce delay', () {
      FakeAsync().run((async) {
        // Arrange
        final dispatcher = _buildDispatcher();
        final loader = FakeLoader<_FakePage<int>>();
        loader.enqueueValue(_page(<int>[1, 2, 3]));

        // Act
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
        final loader = FakeLoader<_FakePage<int>>();
        loader.enqueueValue(_page(<int>[10, 20]));

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
        final seedLoader = FakeLoader<_FakePage<int>>();
        final firstPage = _page(<int>[1, 2, 3]);
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
        final searchLoader = FakeLoader<_FakePage<int>>();
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

    test('minLength rejection on an already-empty list: no notification', () {
      FakeAsync().run((async) {
        // Arrange — items are empty right after construction.
        final dispatcher = _buildDispatcher();
        final loader = FakeLoader<_FakePage<int>>();
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
        final loader = FakeLoader<_FakePage<int>>();
        loader.enqueueValue(_page(<int>[100, 200, 300]));

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
        final loader = FakeLoader<_FakePage<int>>();
        loader.enqueueValue(_page(<int>[7, 8]));

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
        final loader = FakeLoader<_FakePage<int>>();
        loader.enqueueValue(_page(<int>[1, 2]));
        loader.enqueueValue(_page(<int>[3, 4]));
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
          searchStrategy: ACDebouncedSearchStrategy(
            debounce: Duration.zero,
            minLength: 1,
          ),
        );
        final loader = FakeLoader<_FakePage<int>>();
        loader.enqueueValue(_page(<int>[5, 6]));

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

  group('ACPageDispatcher — loadMore search semantics (US2, D-04)', () {
    test('loadMore with any query does NOT apply debounce: loader runs now', () {
      FakeAsync().run((async) {
        // Arrange — seed items with a normal reload first.
        final dispatcher = _buildDispatcher();
        final loader = FakeLoader<_FakePage<int>>()
          ..enqueueValue(_page(<int>[1, 2]))
          ..enqueueValue(_page(<int>[3, 4]));
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
              params: const _TestParams(query: 'abc'),
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
        final loader = FakeLoader<_FakePage<int>>()
          ..enqueueValue(_page(<int>[1, 2]))
          ..enqueueValue(_page(<int>[3, 4]));
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
              params: const _TestParams(query: 'ab'),
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
        final loader = FakeLoader<_FakePage<int>>()
          ..enqueueValue(_page(<int>[1, 2]))
          ..enqueueValue(_page(<int>[3, 4]))
          ..enqueueValue(_page(<int>[5, 6]));
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
              params: const _TestParams(query: 'different'),
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
