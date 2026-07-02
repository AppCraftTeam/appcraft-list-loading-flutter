import 'package:flutter/foundation.dart';

import 'ac_cancel_strategy.dart';
import 'ac_page.dart';
import 'ac_params.dart';
import 'ac_search_strategy.dart';

/// Self-contained dispatcher for page-model pagination over a plain
/// `List<T>`.
///
/// Unlike `ACDispatcher`, this class does not compose a separate parser:
/// item extraction and the `hasMore` calculation are built in. The loader
/// returns a page model [R] that mixes in [ACPage] — its `items` become the
/// accumulated [items], and `hasMore` is read directly from the model
/// (`result.hasMore`), instead of being derived from an offset rule.
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
/// - [P] — the loading parameters type mixing in [ACParamsMixin];
/// - [R] — the page model returned by the loader, mixing in [ACPage];
/// - [T] — the list element type.
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
class ACPageDispatcher<P extends ACParamsMixin, R extends ACPage<T>, T>
    extends ChangeNotifier {
  /// Creates a dispatcher with an optional [searchStrategy].
  ///
  /// If [searchStrategy] is not provided, an [ACDebouncedSearchStrategy]
  /// with defaults is used (debounce `300ms`, `minLength = 3`). The
  /// strategy is set once and does not change afterwards.
  ACPageDispatcher({
    ACSearchStrategy? searchStrategy,
  }) : searchStrategy = searchStrategy ?? ACDebouncedSearchStrategy();

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
  // ignore: unnecessary_getters_setters
  bool get hasMore => _hasMore;

  /// Manually sets the next-page flag.
  ///
  /// Overrides the `hasMore` value read from the last loaded page. It acts
  /// as the guard for [loadMore]: when set to `false`, subsequent
  /// [loadMore] calls are ignored; when set to `true`, [loadMore] may run
  /// again. [notifyListeners] is **not** invoked (parity with the loading
  /// flags: changing `hasMore` does not notify subscribers). Setting this
  /// flag does not cancel an active load.
  set hasMore(bool value) => _hasMore = value;

  /// The last page model that was successfully returned by the loader.
  ///
  /// Updated after every successful [reload] or [loadMore] — stores the
  /// same [R] reference returned by the loader (no defensive copy).
  ///
  /// `null` until the first successful load. Not reset by:
  /// - rejection by `minLength` in [reload];
  /// - exceptions thrown by the loader;
  /// - [cancel] before the wait completes.
  ///
  /// Reset to `null` by [dispose].
  R? get lastResult => _lastResult;

  /// Mutates the accumulated items in place.
  ///
  /// This is the **only sanctioned write path** into the internal list:
  /// the [items] getter returns a `List.unmodifiable` view, so external
  /// code cannot mutate the accumulated items directly. The [update]
  /// callback receives the **mutable** backing list and may perform any
  /// number of changes (add, remove, reorder, replace); all of them are
  /// batched into a **single** [notifyListeners] call emitted on success.
  ///
  /// After [dispose] this is a no-op: the callback is not invoked and no
  /// notification is emitted.
  ///
  /// If [update] throws, the exception is **propagated outside** and
  /// [notifyListeners] is **not** invoked; there is no rollback of the
  /// changes applied before the throw.
  ///
  /// [mutate] does not cancel an active load: an in-flight [reload] will
  /// overwrite the mutated items when it resolves. To seed the list
  /// before a load, call [cancel] first.
  void mutate(void Function(List<T> items) update) {
    if (_disposed) return;
    update(_items);
    notifyListeners();
  }

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
  ///   runs the loader, replaces the accumulated items with the page
  ///   model's `items` and invokes [notifyListeners].
  ///
  /// Any active load is cancelled before a new one starts via the
  /// previously stored [ACCancelStrategy].
  ///
  /// [load] is called with the provided [params]; the returned page
  /// model's `items` replace the accumulated items. Loader exceptions are
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
  /// The returned page model's `items` are **appended** to the end of the
  /// existing list; [hasMore] is read from the page model
  /// (`result.hasMore`). On a successful load [notifyListeners] is invoked.
  ///
  /// Loader exceptions are **propagated outside**; the [isLoading] flag
  /// is reset before the exception leaves the method. Accumulated items
  /// are not mutated on error.
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
  /// Does not reset the accumulated [items], the [hasMore] flag or
  /// [lastResult]. If no load is in progress, this is a safe no-op. After
  /// [dispose] it is also safe (does nothing). [notifyListeners] is not
  /// invoked because [items] do not change.
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
  /// resources, resets [lastResult] and marks the dispatcher as disposed.
  /// A repeated [dispose] is an idempotent no-op. Any public methods
  /// called after [dispose] become no-ops and do not mutate state.
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
  /// page model's `items`; when `replace == false` they are appended
  /// (loadMore).
  ///
  /// [cancelStrategy] is selected by priority: argument -> a new
  /// [ACOperationCancelStrategy]. The selected instance is stored in
  /// `_activeCancel` so that the next [reload] can cancel it.
  ///
  /// Item extraction is built in — the loader returns a page model whose
  /// `items` are the list of items and whose `hasMore` drives the
  /// next-page flag. Loader exceptions are not caught: `try/finally`
  /// guarantees that [_isLoading] is reset before the exception is
  /// propagated.
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

      final newItems = result.items;
      final newHasMore = result.hasMore;

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
