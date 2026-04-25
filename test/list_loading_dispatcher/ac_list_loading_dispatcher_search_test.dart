// ignore_for_file: cascade_invocations, unused_element_parameter, prefer_const_constructors
import 'package:appcraft_list_loading_flutter/src/list_loading_dispatcher/src/ac_list_loading_dispatcher.dart';
import 'package:appcraft_list_loading_flutter/src/list_loading_dispatcher/src/ac_list_loading_params.dart';
import 'package:appcraft_list_loading_flutter/src/list_loading_dispatcher/src/ac_search_strategy.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_loader.dart';

/// Offset-based params used with [ACDefaultListLoadingDispatcher].
final class _TestParams
    with ACListLoadingParamsMixin, ACOffsetListLoadingParamsMixin {
  const _TestParams({this.limit, this.offset, this.query});

  @override
  final int? limit;
  @override
  final int? offset;
  @override
  final String? query;
}

ACDefaultListLoadingDispatcher<_TestParams, int> _buildDispatcher({
  ACSearchStrategy? searchStrategy,
}) =>
    ACDefaultListLoadingDispatcher<_TestParams, int>(
      searchStrategy: searchStrategy,
    );

void main() {
  group('ACListLoadingDispatcher — search in reload (US2)', () {
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
        'called', () {
      FakeAsync().run((async) {
        // Arrange — seed items so we can observe clearing.
        final dispatcher = _buildDispatcher();
        final seedLoader = FakeLoader<List<int>>();
        seedLoader.enqueueValue(<int>[1, 2, 3]);
        dispatcher
            .reload(
              params: const _TestParams(),
              load: seedLoader.call,
            )
            .ignore();
        async.flushMicrotasks();
        expect(dispatcher.items, equals(<int>[1, 2, 3]));

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
        'two successive reloads within debounce window: first timer is '
        'cancelled, second query wins', () {
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

        // Act — elapse the rest of the second reload's debounce (total 300ms
        // from the second schedule call).
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
        'repeated reload with same query after it was applied: load starts '
        'immediately (no debounce)', () {
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

    test(
        'reload(query: null) after a search resets internal state; the '
        'next search of the previous query is debounced again', () {
      FakeAsync().run((async) {
        // Arrange — apply 'john' first.
        final dispatcher = _buildDispatcher();
        final loader = FakeLoader<List<int>>();
        loader.enqueueValue(<int>[1, 2]);
        loader.enqueueValue(<int>[5, 6]);
        loader.enqueueValue(<int>[7, 8]);
        dispatcher
            .reload(
              params: const _TestParams(query: 'john'),
              load: loader.call,
            )
            .ignore();
        async.elapse(const Duration(milliseconds: 300));
        async.flushMicrotasks();
        expect(loader.callCount, 1);

        // Act 1 — reload with null query resets immediately.
        dispatcher
            .reload(
              params: const _TestParams(),
              load: loader.call,
            )
            .ignore();
        async.flushMicrotasks();
        expect(loader.callCount, 2);
        expect(dispatcher.items, equals(<int>[5, 6]));

        // Act 2 — searching for 'john' again must be debounced.
        dispatcher
            .reload(
              params: const _TestParams(query: 'john'),
              load: loader.call,
            )
            .ignore();
        async.elapse(const Duration(milliseconds: 100));
        async.flushMicrotasks();
        expect(loader.callCount, 2,
            reason: 'null reset must have cleared last-applied; search '
                'must re-debounce');

        // Advance past the debounce — loader fires now.
        async.elapse(const Duration(milliseconds: 300));
        async.flushMicrotasks();
        expect(loader.callCount, 3);
        expect(dispatcher.items, equals(<int>[7, 8]));

        dispatcher.dispose();
      });
    });

    test(
        'dispose during a pending debounce cancels the timer; loader does '
        'not fire after elapse', () {
      FakeAsync().run((async) {
        // Arrange
        final dispatcher = _buildDispatcher();
        final loader = FakeLoader<List<int>>();
        loader.enqueueValue(<int>[1, 2]);

        // Act — start a search; before debounce fires, dispose.
        dispatcher
            .reload(
              params: const _TestParams(query: 'alex'),
              load: loader.call,
            )
            .ignore();
        async.elapse(const Duration(milliseconds: 100));
        dispatcher.dispose();
        async.flushMicrotasks();

        // Elapse past the debounce boundary — the timer must be cancelled.
        async.elapse(const Duration(milliseconds: 500));
        async.flushMicrotasks();

        // Assert
        expect(loader.callCount, 0,
            reason: 'dispose must cancel pending debounce timer');
      });
    });
  });

  group('ACListLoadingDispatcher — loadMore search semantics (US2)', () {
    test(
        'loadMore with any query does NOT apply debounce: loader runs '
        'immediately', () {
      FakeAsync().run((async) {
        // Arrange — seed items with a normal reload first (hasMore=true via
        // null limit).
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
        'loadMore with query shorter than minLength: minLength check does '
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
        'loadMore does NOT mutate last-applied query: subsequent reload '
        'with the original query still skips debounce', () {
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
        // It must NOT be.
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
