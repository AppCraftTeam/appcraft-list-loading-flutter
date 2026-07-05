// ignore_for_file: cascade_invocations, unused_element_parameter, prefer_const_constructors
import 'package:appcraft_list_loading_flutter/src/ac_list_dispatcher.dart';
import 'package:appcraft_list_loading_flutter/src/ac_page.dart';
import 'package:appcraft_list_loading_flutter/src/ac_page_dispatcher.dart';
import 'package:appcraft_list_loading_flutter/src/ac_params.dart';
import 'package:appcraft_list_loading_flutter/src/ac_search_debouncer.dart';
import 'package:appcraft_list_loading_flutter/src/ac_search_strategy.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/fake_loader.dart';

/// Offset-based params for [ACListDispatcher]: the loader returns a bare
/// `List<int>` and `hasMore` is recomputed from `params.limit`.
final class _ListParams with ACParamsMixin, ACOffsetParamsMixin {
  const _ListParams({this.limit, this.offset, this.query});

  @override
  final int? limit;
  @override
  final int? offset;
  @override
  final String? query;
}

/// Page-model params for [ACPageDispatcher]: `hasMore` comes from the page.
final class _PageParams with ACParamsMixin {
  const _PageParams({this.limit, this.query});

  @override
  final int? limit;
  @override
  final String? query;
}

/// Minimal page-model DTO carrying its own `hasMore` flag.
final class _FakePage<T> with ACPage<T> {
  const _FakePage({required this.items, required this.hasMore});

  @override
  final List<T> items;
  @override
  final bool hasMore;
}

/// A search strategy that launches immediately (no debounce, no minLength
/// gate) so tests control timing purely via the loader.
ACSearchStrategy _immediateStrategy() => ACSearchDebouncer(
      debounce: Duration.zero,
      minLength: 0,
    );

ACListDispatcher<_ListParams, int> _buildListDispatcher() =>
    ACListDispatcher<_ListParams, int>(searchStrategy: _immediateStrategy());

ACPageDispatcher<_PageParams, _FakePage<int>, int> _buildPageDispatcher() =>
    ACPageDispatcher<_PageParams, _FakePage<int>, int>(
      searchStrategy: _immediateStrategy(),
    );

void main() {
  group('hasMore default before first load — ACListDispatcher (US1)', () {
    test('freshDispatcher_hasMoreFalse_lastResultNull_isLoadingFalse', () {
      // Arrange & Act — a brand-new dispatcher, no load performed.
      final dispatcher = _buildListDispatcher();

      // Assert — the fresh default is hasMore=false with empty, idle state.
      expect(dispatcher.hasMore, isFalse);
      expect(dispatcher.lastResult, isNull);
      expect(dispatcher.isLoading, isFalse);
      expect(dispatcher.items, isEmpty);

      dispatcher.dispose();
    });

    test('loadMoreWithoutReload_noForce_isNoOp', () async {
      // Arrange — fresh dispatcher; hasMore=false blocks a plain loadMore.
      final dispatcher = _buildListDispatcher();
      final loader = FakeLoader<List<int>>();
      loader.enqueueValue(<int>[1, 2]);

      // Act
      await dispatcher.loadMore(
        params: const _ListParams(limit: 2),
        load: loader.call,
      );

      // Assert — loader untouched, items stay empty.
      expect(loader.callCount, equals(0));
      expect(dispatcher.items, isEmpty);
      expect(dispatcher.hasMore, isFalse);

      dispatcher.dispose();
    });

    test('loadMoreWithoutReload_forceTrue_loadsAndAppends', () async {
      // Arrange — fresh dispatcher; force must bypass the hasMore guard.
      final dispatcher = _buildListDispatcher();
      final loader = FakeLoader<List<int>>();
      loader.enqueueValue(<int>[1, 2]);

      // Act
      await dispatcher.loadMore(
        params: const _ListParams(limit: 2),
        load: loader.call,
        force: true,
      );

      // Assert — loader ran and items were appended.
      expect(loader.callCount, equals(1));
      expect(dispatcher.items, equals(<int>[1, 2]));

      dispatcher.dispose();
    });

    test('firstReload_fullPage_hasMoreTrue', () async {
      // Arrange — a full page (result.length >= limit) yields hasMore=true.
      final dispatcher = _buildListDispatcher();
      final loader = FakeLoader<List<int>>();
      loader.enqueueValue(<int>[1, 2]);

      // Act
      await dispatcher.reload(
        params: const _ListParams(limit: 2),
        load: loader.call,
      );

      // Assert
      expect(dispatcher.items, equals(<int>[1, 2]));
      expect(dispatcher.hasMore, isTrue,
          reason: 'result.length (2) >= limit (2) recomputes hasMore=true');

      dispatcher.dispose();
    });

    test('firstReload_partialPage_hasMoreFalse', () async {
      // Arrange — a short page (result.length < limit) yields hasMore=false.
      final dispatcher = _buildListDispatcher();
      final loader = FakeLoader<List<int>>();
      loader.enqueueValue(<int>[1]);

      // Act
      await dispatcher.reload(
        params: const _ListParams(limit: 2),
        load: loader.call,
      );

      // Assert
      expect(dispatcher.items, equals(<int>[1]));
      expect(dispatcher.hasMore, isFalse,
          reason: 'result.length (1) < limit (2) recomputes hasMore=false');

      dispatcher.dispose();
    });
  });

  group('hasMore default before first load — ACPageDispatcher (US1)', () {
    test('freshDispatcher_hasMoreFalse_lastResultNull_isLoadingFalse', () {
      // Arrange & Act — a brand-new dispatcher, no load performed.
      final dispatcher = _buildPageDispatcher();

      // Assert — the fresh default is hasMore=false with empty, idle state.
      expect(dispatcher.hasMore, isFalse);
      expect(dispatcher.lastResult, isNull);
      expect(dispatcher.isLoading, isFalse);
      expect(dispatcher.items, isEmpty);

      dispatcher.dispose();
    });

    test('loadMoreWithoutReload_noForce_isNoOp', () async {
      // Arrange — fresh dispatcher; hasMore=false blocks a plain loadMore.
      final dispatcher = _buildPageDispatcher();
      final loader = FakeLoader<_FakePage<int>>();
      loader.enqueueValue(
        const _FakePage<int>(items: <int>[1, 2], hasMore: true),
      );

      // Act
      await dispatcher.loadMore(
        params: const _PageParams(),
        load: loader.call,
      );

      // Assert — loader untouched, items stay empty.
      expect(loader.callCount, equals(0));
      expect(dispatcher.items, isEmpty);
      expect(dispatcher.hasMore, isFalse);

      dispatcher.dispose();
    });

    test('loadMoreWithoutReload_forceTrue_loadsAndAppends', () async {
      // Arrange — fresh dispatcher; force must bypass the hasMore guard.
      final dispatcher = _buildPageDispatcher();
      final loader = FakeLoader<_FakePage<int>>();
      loader.enqueueValue(
        const _FakePage<int>(items: <int>[1, 2], hasMore: true),
      );

      // Act
      await dispatcher.loadMore(
        params: const _PageParams(),
        load: loader.call,
        force: true,
      );

      // Assert — loader ran and items were appended.
      expect(loader.callCount, equals(1));
      expect(dispatcher.items, equals(<int>[1, 2]));

      dispatcher.dispose();
    });

    test('firstReload_pageHasMoreTrue_hasMoreTrue', () async {
      // Arrange — the page model reports hasMore=true.
      final dispatcher = _buildPageDispatcher();
      final loader = FakeLoader<_FakePage<int>>();
      loader.enqueueValue(
        const _FakePage<int>(items: <int>[1, 2], hasMore: true),
      );

      // Act
      await dispatcher.reload(
        params: const _PageParams(),
        load: loader.call,
      );

      // Assert
      expect(dispatcher.items, equals(<int>[1, 2]));
      expect(dispatcher.hasMore, isTrue,
          reason: 'hasMore is read straight from page.hasMore (true)');

      dispatcher.dispose();
    });

    test('firstReload_pageHasMoreFalse_hasMoreFalse', () async {
      // Arrange — the page model reports hasMore=false.
      final dispatcher = _buildPageDispatcher();
      final loader = FakeLoader<_FakePage<int>>();
      loader.enqueueValue(
        const _FakePage<int>(items: <int>[1], hasMore: false),
      );

      // Act
      await dispatcher.reload(
        params: const _PageParams(),
        load: loader.call,
      );

      // Assert
      expect(dispatcher.items, equals(<int>[1]));
      expect(dispatcher.hasMore, isFalse,
          reason: 'hasMore is read straight from page.hasMore (false)');

      dispatcher.dispose();
    });
  });
}
