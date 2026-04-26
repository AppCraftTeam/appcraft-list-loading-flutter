import 'package:flutter/foundation.dart';

import 'ac_cancel_strategy.dart';
import 'ac_list_loading_params.dart';
import 'ac_list_loading_parser.dart';
import 'ac_list_loading_result.dart';
import 'ac_search_strategy.dart';

/// Dispatcher for list loading with pagination and search.
///
/// Encapsulates the loading lifecycle: `reload` restarts the list from
/// scratch, `loadMore` appends the next page, `cancel` aborts the active
/// load without dropping the accumulated items, `dispose` releases
/// resources.
///
/// The dispatcher extends [ChangeNotifier]. State is exposed via the
/// [items], [isLoading] and [hasMore] getters; [notifyListeners] is
/// invoked only when **[items] change** — `ChangeNotifier` subscribers
/// re-read `items` and update the UI on their own. Changes to
/// [isLoading] or [hasMore] without a change in [items] do not trigger
/// a notification; if a consumer needs a spinner, [isLoading] can be
/// read synchronously before/after `reload`/`loadMore` (for example by
/// wrapping the call in `setState`).
///
/// Generic parameters:
/// - [P] — the loading parameters type that mixes in
///   [ACParamsMixin] (and, usually, one of the offset/cursor
///   mixins);
/// - [R] — the loader's result type. May be a plain `List<T>` or any
///   DTO — extracting items and `hasMore` is encapsulated in [parser];
/// - [T] — the list element type.
///
/// For typical scenarios the ready facade subclasses are more
/// convenient: [ACDefaultDispatcher] (the loader returns
/// `List<T>`) and [ACCustomDispatcher] (the loader returns
/// a DTO that mixes in [ACResult]).
///
/// Search behaviour is configured via [searchStrategy] and applies only
/// in [reload]: debounce for a changed query, rejection when `minLength`
/// is not met (with items cleared), immediate launch for an empty or
/// matching query. In [loadMore] the search strategy is ignored: the
/// query from params is passed to the loader as-is, debounce and the
/// minLength check are not applied.
///
/// Loader errors are **not** caught: an exception thrown inside
/// `load(params)` propagates out of [reload]/[loadMore]. The
/// [isLoading] flag is guaranteed to be reset (via `try/finally`).
class ACDispatcher<P extends ACParamsMixin, R, T>
    extends ChangeNotifier {
  /// Creates a dispatcher with the required [parser] and an optional
  /// [searchStrategy].
  ///
  /// [parser] is used on every completed loader call to extract items
  /// and the `hasMore` flag from the result.
  ///
  /// If [searchStrategy] is not provided, an
  /// [ACDebouncedSearchStrategy] with defaults is used (debounce
  /// `300ms`, `minLength = 3`). The strategy is set once and does not
  /// change afterwards.
  ACDispatcher({
    required this.parser,
    ACSearchStrategy? searchStrategy,
  }) : searchStrategy = searchStrategy ?? ACDebouncedSearchStrategy();

  /// Strategy for extracting items and `hasMore` from the loader result.
  final ACParser<P, R, T> parser;

  /// Search behaviour strategy applied in [reload].
  final ACSearchStrategy searchStrategy;

  final List<T> _items = <T>[];
  bool _isLoading = false;
  bool _hasMore = true;
  bool _disposed = false;
  ACCancelStrategy? _activeCancel;
  R? _lastResult;

  /// Unmodifiable view of the accumulated items.
  ///
  /// Returned via `List.unmodifiable` — attempting to mutate it from
  /// the outside throws `UnsupportedError`.
  List<T> get items => List<T>.unmodifiable(_items);

  /// Whether a load is currently in progress.
  ///
  /// Read synchronously; [notifyListeners] is **not** invoked when this
  /// flag changes. If a reactive spinner is needed, wrap the
  /// `reload`/`loadMore` call in `setState` or its equivalent.
  bool get isLoading => _isLoading;

  /// Whether there are more items to load via [loadMore].
  ///
  /// Read synchronously; [notifyListeners] is **not** invoked when this
  /// flag changes without a change in [items].
  bool get hasMore => _hasMore;

  /// The last result that was successfully returned by the loader.
  ///
  /// Updated after every successful [reload] or [loadMore] — stores the
  /// raw [R] object as returned by the loader (the same reference, no
  /// defensive copy). Useful for cursor pagination and DTO scenarios
  /// where the response carries metadata beyond `items`/`hasMore` —
  /// for example, `nextCursor`, `totalCount`, or server-side pagination
  /// tokens.
  ///
  /// `null` until the first successful load. Not reset by:
  /// - rejection by `minLength` in [reload];
  /// - exceptions thrown by the loader or parser;
  /// - [cancel] before the wait completes.
  ///
  /// Reset to `null` by [dispose].
  R? get lastResult => _lastResult;

  /// Reloads the list.
  ///
  /// Behaviour is determined by [searchStrategy]. The strategy receives
  /// `params.query` and returns:
  /// - `null` — rejection by `minLength`: items are cleared,
  ///   `hasMore = false`, the loader is **not** called.
  ///   [notifyListeners] is invoked only if the list was non-empty
  ///   (i.e. [items] actually changed);
  /// - `Future<void>` — the load should be started when it resolves
  ///   (immediately or after a debounce). On resolve the dispatcher
  ///   runs the loader, replaces the accumulated items with the result
  ///   and invokes [notifyListeners].
  ///
  /// Any active load is cancelled before a new one starts via the
  /// previously stored [ACCancelStrategy].
  ///
  /// [load] is called with the provided [params]. The result type [R]
  /// is determined by the dispatcher's generic; extraction of items and
  /// `hasMore` is performed by [parser]. Loader/parser exceptions are
  /// **propagated outside**; the [isLoading] flag is reset before the
  /// exception leaves the method.
  ///
  /// A result that arrives after [dispose], or after a newer [reload]
  /// has already started, is ignored (it is not applied to the state
  /// and does not notify).
  ///
  /// [cancelStrategy] — an optional cancellation strategy specifically
  /// for this load. Priority: argument -> a new
  /// [ACOperationCancelStrategy] for each call. In the minLength
  /// rejection branch [cancelStrategy] is not used: the load does not
  /// start.
  Future<void> reload({
    required P params,
    required Future<R> Function(P params) load,
    ACCancelStrategy? cancelStrategy,
  }) async {
    if (_disposed) return;

    // Set the loading flag SYNCHRONOUSLY so that code that runs right
    // after `dispatcher.reload(...)` immediately sees `isLoading == true`
    // without waiting for the debounce or any internal awaits.
    _isLoading = true;

    final schedule = searchStrategy.schedule(params.query);
    if (schedule == null) {
      // Rejection by minLength — clear items.
      final previousCancel = _activeCancel;
      _activeCancel = null;
      if (previousCancel != null) {
        await previousCancel.cancel();
      }
      if (_disposed) return;

      final wasNonEmpty = _items.isNotEmpty;
      _items.clear();
      _hasMore = false;
      _isLoading = false;
      if (wasNonEmpty) notifyListeners();
      return;
    }

    await schedule;
    if (_disposed) return;

    await _runLoad(
      params: params,
      load: load,
      replace: true,
      cancelStrategy: cancelStrategy,
    );
  }

  /// Loads the next page.
  ///
  /// Ignored (without an error and without changing state) if:
  /// - another load is already in progress (`isLoading == true`);
  /// - [hasMore] == `false`;
  /// - the dispatcher has already been `dispose`-d.
  ///
  /// The search strategy is not applied in [loadMore]:
  /// [searchStrategy] is not invoked, there is no debounce and the
  /// minLength check is skipped. The query from [params] is passed to
  /// [load] as-is.
  ///
  /// Items extracted by [parser] are **appended** to the end of the
  /// existing list; [hasMore] is updated from the parser result. On a
  /// successful load [notifyListeners] is invoked.
  ///
  /// Loader/parser exceptions are **propagated outside**; the
  /// [isLoading] flag is reset before the exception leaves the method.
  /// Accumulated items are not mutated on error.
  ///
  /// [cancelStrategy] — an optional cancellation strategy specifically
  /// for this load. Priority: argument -> a new
  /// [ACOperationCancelStrategy] for each call.
  Future<void> loadMore({
    required P params,
    required Future<R> Function(P params) load,
    ACCancelStrategy? cancelStrategy,
  }) async {
    if (_disposed) return;
    if (_isLoading) return;
    if (!_hasMore) return;

    await _runLoad(
      params: params,
      load: load,
      replace: false,
      cancelStrategy: cancelStrategy,
    );
  }

  /// Cancels the active load (including the pending timer in
  /// [searchStrategy]).
  ///
  /// Does not reset the accumulated [items] or the [hasMore] flag. If
  /// no load is in progress, this is a safe no-op. After [dispose] it
  /// is also safe (does nothing). [notifyListeners] is not invoked
  /// because [items] do not change.
  Future<void> cancel() async {
    if (_disposed) return;

    searchStrategy.cancel();

    final previousCancel = _activeCancel;
    _activeCancel = null;
    await previousCancel?.cancel();
    if (_disposed) return;

    _isLoading = false;
  }

  /// Releases resources.
  ///
  /// Cancels the active load and the [searchStrategy] pending timer
  /// (cancellation errors are ignored), releases the search strategy's
  /// resources and marks the dispatcher as disposed. A repeated
  /// [dispose] is an idempotent no-op. Any public methods called after
  /// [dispose] become no-ops and do not mutate state.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;

    searchStrategy.dispose();

    // Cancel the active load fire-and-forget: errors are ignored,
    // releasing resources takes priority.
    final previousCancel = _activeCancel;
    _activeCancel = null;
    _lastResult = null;
    if (previousCancel != null) {
      // Don't await: ChangeNotifier.dispose is synchronous. The result
      // of cancel is no longer needed by anyone.
      previousCancel.cancel().ignore();
    }

    super.dispose();
  }

  /// Common loading routine for [reload] and [loadMore].
  ///
  /// When `replace == true` the accumulated items are replaced with the
  /// loader result; when `replace == false` they are appended (loadMore).
  ///
  /// [cancelStrategy] is selected by priority: argument -> a new
  /// [ACOperationCancelStrategy]. The selected instance is stored in
  /// `_activeCancel` so that the next [reload] can cancel it.
  ///
  /// Extraction of items and `hasMore` is delegated to [parser].
  /// Loader/parser exceptions are not caught: `try/finally` guarantees
  /// that [_isLoading] is reset before the exception is propagated.
  Future<void> _runLoad({
    required P params,
    required Future<R> Function(P params) load,
    required bool replace,
    ACCancelStrategy? cancelStrategy,
  }) async {
    if (_disposed) return;

    final previousCancel = _activeCancel;
    final capturedCancel = cancelStrategy ?? ACOperationCancelStrategy();
    _activeCancel = capturedCancel;
    _isLoading = true;

    if (previousCancel != null) {
      await previousCancel.cancel();
    }
    if (_disposed || !identical(_activeCancel, capturedCancel)) {
      return;
    }

    try {
      final result = await capturedCancel.run<R>(load(params));
      if (_disposed || !identical(_activeCancel, capturedCancel)) return;
      if (result == null) return; // cancelled

      final newItems = parser.extractItems(params, result);
      final newHasMore = parser.hasMore(params, result);

      if (replace) {
        _items
          ..clear()
          ..addAll(newItems);
      } else {
        _items.addAll(newItems);
      }
      _hasMore = newHasMore;
      _lastResult = result;
      notifyListeners();
    } finally {
      if (!_disposed && identical(_activeCancel, capturedCancel)) {
        _isLoading = false;
      }
    }
  }
}

/// Facade dispatcher for offset pagination with a plain `List<T>`
/// response.
///
/// Uses [ACDefaultParser] — items are taken directly from
/// the result, `hasMore` is computed as
/// `result.length >= params.limit`.
///
/// Example:
///
/// ```dart
/// final dispatcher = ACDefaultDispatcher<UserListParams, User>();
/// await dispatcher.reload(
///   params: const UserListParams(offset: 0, limit: 20),
///   load: (p) => api.fetchUsers(offset: p.offset, limit: p.limit),
/// );
/// ```
///
/// **Extension point**: can be extended to customize loading behavior.
/// Overrides of `notifyListeners`, `dispose`, or internal state mutation
/// must respect the `ChangeNotifier` contract; `super.dispose()` is
/// required.
class ACDefaultDispatcher<
        P extends ACOffsetParamsMixin, T>
    extends ACDispatcher<P, List<T>, T> {
  /// Creates a dispatcher with [ACDefaultParser] and an
  /// optional [searchStrategy].
  ACDefaultDispatcher({
    super.searchStrategy,
  }) : super(
          parser: ACDefaultParser<P, T>(),
        );
}

/// Facade dispatcher for DTOs that mix in [ACResult].
///
/// Uses [ACResultParser] — items and `hasMore` are taken
/// from the corresponding getters on the result.
///
/// Example:
///
/// ```dart
/// final dispatcher =
///     ACCustomDispatcher<UserCursorParams, UserPage, User>();
/// await dispatcher.reload(
///   params: const UserCursorParams(cursor: null),
///   load: (p) => api.fetchUsers(cursor: p.cursor),
/// );
/// ```
///
/// **Extension point**: can be extended to customize loading behavior.
/// Overrides of `notifyListeners`, `dispose`, or internal state mutation
/// must respect the `ChangeNotifier` contract; `super.dispose()` is
/// required.
class ACCustomDispatcher<
        P extends ACParamsMixin,
        R extends ACResult<T>,
        T> extends ACDispatcher<P, R, T> {
  /// Creates a dispatcher with [ACResultParser] and an
  /// optional [searchStrategy].
  ACCustomDispatcher({
    super.searchStrategy,
  }) : super(
          parser: ACResultParser<P, R, T>(),
        );
}
