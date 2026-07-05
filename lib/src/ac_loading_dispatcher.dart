import 'package:flutter/foundation.dart';

import 'ac_cancel_strategy.dart';
import 'ac_dispatcher_operation.dart';
import 'ac_params.dart';
import 'ac_search_strategy.dart';

/// Shared loading engine for paginated dispatchers.
///
/// Encapsulates the full loading lifecycle — search scheduling, cancellation
/// of a previous load, staleness guards, the `try/finally` reset of
/// [isLoading] and the commit of [lastResult] — in a single place. Concrete
/// dispatchers (`ACListDispatcher`, `ACPageDispatcher`) extend this class and
/// only provide the collection state and a handful of extension points
/// ([hasMore], [onLoadSuccess], [onLoadRejected]).
///
/// The engine is deliberately agnostic about *items*: it works purely with
/// the loader **result** type [T]. `ACListDispatcher` binds `T = List<Item>`,
/// `ACPageDispatcher` binds `T = R extends ACPage<Item>`. Because
/// [lastResult] is typed `T?`, each subclass inherits a precisely typed
/// `lastResult` (`List<Item>?` / `R?`) without declaring its own getter.
///
/// The dispatcher extends [ChangeNotifier]. The engine itself never calls
/// [notifyListeners]; notifications are emitted by the subclass hooks
/// ([onLoadSuccess], [onLoadRejected]) only when the observed collection
/// actually changes. Changes to [isLoading] or [hasMore] on their own do not
/// notify subscribers.
///
/// Generic parameters:
/// - [Params] — the loading parameters type mixing in [ACParamsMixin];
/// - [T] — the loader result type (not the element type).
///
/// This class is a public extension point: third-party code may subclass it
/// to implement non-standard pagination while reusing the loading engine.
abstract class ACLoadingDispatcher<Params extends ACParamsMixin, T>
    extends ChangeNotifier {
  /// Creates a dispatcher with an optional [searchStrategy].
  ///
  /// If [searchStrategy] is not provided, an [ACDebouncedSearchStrategy]
  /// with defaults is used (debounce `300ms`, `minLength = 3`). The
  /// strategy is set once and does not change afterwards.
  ACLoadingDispatcher({
    ACSearchStrategy? searchStrategy,
  }) : searchStrategy = searchStrategy ?? ACDebouncedSearchStrategy();

  /// Search behaviour strategy applied in [reload].
  final ACSearchStrategy searchStrategy;

  bool _isReloading = false;
  bool _isLoadingMore = false;
  final ValueNotifier<bool> _loadingNotifier = ValueNotifier<bool>(false);
  bool _disposed = false;
  ACCancelStrategy? _activeCancel;
  T? _lastResult;
  ACDispatcherOperation<Params, T>? _lastOperation;
  final ValueNotifier<Object?> _errorNotifier = ValueNotifier<Object?>(null);

  /// Whether a load is currently in progress.
  ///
  /// `true` while **any** load runs — either a [reload] or a [loadMore]; it is
  /// the derived disjunction [isReloading] `||` [isLoadingMore]. The semantics
  /// are unchanged from previous versions.
  ///
  /// Read synchronously; [notifyListeners] is **not** invoked when this
  /// flag changes. For a reactive spinner subscribe to [loadingListenable]
  /// instead of wrapping the call in `setState`.
  bool get isLoading => _isReloading || _isLoadingMore;

  /// Whether a [reload] is currently in progress.
  ///
  /// Read synchronously. Mutually exclusive with [isLoadingMore]: during an
  /// active load exactly one of the two is `true`; outside a load both are
  /// `false`. Changing this flag does not invoke [notifyListeners].
  bool get isReloading => _isReloading;

  /// Whether a [loadMore] is currently in progress.
  ///
  /// Read synchronously. Mutually exclusive with [isReloading]: during an
  /// active load exactly one of the two is `true`; outside a load both are
  /// `false`. Changing this flag does not invoke [notifyListeners].
  bool get isLoadingMore => _isLoadingMore;

  /// Reactive channel mirroring [isLoading].
  ///
  /// Its `value` always equals [isLoading] and it notifies its listeners on
  /// every actual `false`↔`true` transition, synchronously with the change
  /// (including the synchronous start of [reload]). Repeated assignment of the
  /// same value is de-duplicated by the underlying [ValueNotifier], so no-op
  /// calls (e.g. [loadMore] while `!hasMore`) emit nothing.
  ///
  /// This channel is independent of the `notifyListeners` contract, which
  /// fires only when the observed collection changes: subscribe here to drive
  /// a spinner from the loading state without coupling to item updates.
  ///
  /// The resource is released by [dispose].
  ValueListenable<bool> get loadingListenable => _loadingNotifier;

  /// The last result that was successfully returned by the loader.
  ///
  /// Updated after every successful [reload] or [loadMore] — stores the
  /// same [T] reference returned by the loader (no defensive copy).
  ///
  /// `null` until the first successful load. Not reset by:
  /// - rejection by `minLength` in [reload];
  /// - exceptions thrown by the loader;
  /// - [cancel] before the wait completes.
  ///
  /// Reset to `null` by [dispose].
  T? get lastResult => _lastResult;

  /// The last operation captured for [retry] and introspection.
  ///
  /// A [reload] is recorded at the very start of the call; a [loadMore] is
  /// recorded only after passing every guard (a no-op `loadMore` does not
  /// overwrite the previous operation). Pattern-match the sealed variants
  /// ([ACReloadOperation] / [ACLoadMoreOperation]) to inspect it.
  ///
  /// `null` until the first operation. Reset to `null` by [dispose].
  ACDispatcherOperation<Params, T>? get lastOperation => _lastOperation;

  /// The error thrown by the last completed load, or `null` if it succeeded.
  ///
  /// Set when an **active** (non-stale) load throws — the exception is still
  /// propagated by [reload]/[loadMore]. Cleared to `null` by a successful
  /// load. Not touched by [cancel] or a `minLength` rejection.
  ///
  /// Always equals [errorListenable]`.value`. Reset to `null` by [dispose].
  Object? get lastError => _errorNotifier.value;

  /// Reactive channel mirroring [lastError].
  ///
  /// Its `value` always equals [lastError] and it notifies its listeners only
  /// on an actual value change (the underlying [ValueNotifier] de-duplicates
  /// repeated assignments of the same error). This channel is independent of
  /// the `notifyListeners` contract: changing [lastError] does not invoke
  /// [notifyListeners].
  ///
  /// The resource is released by [dispose].
  ValueListenable<Object?> get errorListenable => _errorNotifier;

  /// Whether there are more items to load via [loadMore].
  ///
  /// Implemented by the subclass; read by the [loadMore] guard.
  bool get hasMore;

  /// Sets the loading flags and syncs [loadingListenable] in one place.
  ///
  /// Assigns [isReloading] and [isLoadingMore] and pushes the derived
  /// [isLoading] (`reloading || loadingMore`) into [loadingListenable]; the
  /// [ValueNotifier] de-duplicates unchanged values. Must only be called on
  /// non-disposed paths — after [dispose] the notifier is released.
  void _setLoading({required bool reloading, required bool loadingMore}) {
    _isReloading = reloading;
    _isLoadingMore = loadingMore;
    _loadingNotifier.value = reloading || loadingMore;
  }

  /// Reloads from scratch.
  ///
  /// Behaviour is determined by [searchStrategy]. The strategy receives
  /// `params.query` and returns:
  /// - `null` — rejection by `minLength`: [onLoadRejected] is invoked, the
  ///   loader is **not** called;
  /// - `Future<void>` — the load should be started when it resolves
  ///   (immediately or after a debounce). On resolve the dispatcher runs
  ///   the loader via [runLoad] with `replace: true`.
  ///
  /// Any active load is cancelled before a new one starts via the
  /// previously stored [ACCancelStrategy].
  ///
  /// [load] is called with the provided [params]. Loader exceptions are
  /// **propagated outside**; the [isLoading] flag is reset before the
  /// exception leaves the method.
  ///
  /// A result that arrives after [dispose], or after a newer [reload] has
  /// already started, is ignored (it is not applied to the state and does
  /// not notify).
  ///
  /// [cancelStrategy] — an optional cancellation strategy specifically for
  /// this load. Priority: argument -> a new [ACOperationCancelStrategy] for
  /// each call. In the minLength rejection branch [cancelStrategy] is not
  /// used: the load does not start.
  Future<void> reload({
    required Params params,
    required Future<T> Function(Params params) load,
    ACCancelStrategy? cancelStrategy,
  }) async {
    if (_disposed) return;

    _lastOperation = ACReloadOperation(params: params, load: load);

    // Set the loading flag SYNCHRONOUSLY so that code that runs right
    // after `dispatcher.reload(...)` immediately sees `isLoading == true`
    // without waiting for the debounce or any internal awaits.
    _setLoading(reloading: true, loadingMore: false);

    final schedule = searchStrategy.schedule(params.query);
    if (schedule == null) {
      // Rejection by minLength — delegate collection reset to the subclass.
      final previousCancel = _activeCancel;
      _activeCancel = null;
      if (previousCancel != null) {
        await previousCancel.cancel();
      }
      if (_disposed) return;

      _setLoading(reloading: false, loadingMore: false);
      onLoadRejected();
      return;
    }

    await schedule;
    if (_disposed) return;

    await runLoad(
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
  /// The search strategy is not applied in [loadMore]: [searchStrategy] is
  /// not invoked, there is no debounce and the minLength check is skipped.
  /// The query from [params] is passed to [load] as-is.
  ///
  /// The load runs via [runLoad] with `replace: false`. Loader exceptions
  /// are **propagated outside**; the [isLoading] flag is reset before the
  /// exception leaves the method.
  ///
  /// [cancelStrategy] — an optional cancellation strategy specifically for
  /// this load. Priority: argument -> a new [ACOperationCancelStrategy] for
  /// each call.
  ///
  /// [force] — when `true`, bypasses **only** the [hasMore] `== false` guard,
  /// forcing a load even when the subclass reports no more pages. The other
  /// guards are preserved: the call is still ignored while another load is in
  /// progress (`isLoading == true`) or after [dispose]. The flag is one-shot —
  /// it affects only the current call and is not stored; after a successful
  /// load [hasMore] is recomputed as usual by the subclass.
  Future<void> loadMore({
    required Params params,
    required Future<T> Function(Params params) load,
    ACCancelStrategy? cancelStrategy,
    bool force = false,
  }) async {
    if (_disposed) return;
    if (isLoading) return;
    if (!force && !hasMore) return;

    _lastOperation = ACLoadMoreOperation(
      params: params,
      load: load,
      force: force,
    );

    await runLoad(
      params: params,
      load: load,
      replace: false,
      cancelStrategy: cancelStrategy,
    );
  }

  /// Repeats the last captured [lastOperation].
  ///
  /// Re-dispatches through the public [reload]/[loadMore] entry points, so the
  /// [searchStrategy] and every guard apply exactly as on the original call; a
  /// forced [loadMore] is retried with the same `force`. Each retry uses a
  /// fresh default `cancelStrategy`.
  ///
  /// A no-op (returns a completed future) when no operation was captured yet
  /// or after [dispose]. Loader exceptions are propagated as by the underlying
  /// [reload]/[loadMore].
  Future<void> retry() {
    if (_disposed) return Future<void>.value();
    return switch (_lastOperation) {
      null => Future<void>.value(),
      ACReloadOperation(:final params, :final load) =>
        reload(params: params, load: load),
      ACLoadMoreOperation(:final params, :final load, :final force) =>
        loadMore(params: params, load: load, force: force),
    };
  }

  /// Cancels the active load (including the pending timer in
  /// [searchStrategy]).
  ///
  /// Does not reset the collection state or [lastResult]. If no load is in
  /// progress, this is a safe no-op. After [dispose] it is also safe (does
  /// nothing). [notifyListeners] is not invoked because the collection does
  /// not change.
  Future<void> cancel() async {
    if (_disposed) return;

    searchStrategy.cancel();

    final previousCancel = _activeCancel;
    _activeCancel = null;
    await previousCancel?.cancel();
    if (_disposed) return;

    _setLoading(reloading: false, loadingMore: false);
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
    _lastOperation = null;
    if (previousCancel != null) {
      // Don't await: ChangeNotifier.dispose is synchronous. The result
      // of cancel is no longer needed by anyone.
      previousCancel.cancel().ignore();
    }

    _loadingNotifier.dispose();
    _errorNotifier.dispose();

    super.dispose();
  }

  /// Common loading routine for [reload] and [loadMore] — the single copy
  /// of the loading state machine.
  ///
  /// When `replace == true` the loader result replaces the collection; when
  /// `replace == false` it is appended (loadMore). The concrete write is
  /// delegated to [onLoadSuccess].
  ///
  /// [cancelStrategy] is selected by priority: argument -> a new
  /// [ACOperationCancelStrategy]. The selected instance is stored in
  /// `_activeCancel` so that the next [reload] can cancel it and so that
  /// stale results (from a superseded load) are ignored via an
  /// `identical(_activeCancel, captured)` guard.
  ///
  /// On a successful, non-stale load [lastResult] is committed first, then
  /// [onLoadSuccess] applies the result. Loader exceptions are not caught:
  /// `try/finally` guarantees that [isLoading] is reset before the exception
  /// is propagated.
  @protected
  Future<void> runLoad({
    required Params params,
    required Future<T> Function(Params params) load,
    required bool replace,
    ACCancelStrategy? cancelStrategy,
  }) async {
    if (_disposed) return;

    final previousCancel = _activeCancel;
    final capturedCancel = cancelStrategy ?? ACOperationCancelStrategy();
    _activeCancel = capturedCancel;
    _setLoading(reloading: replace, loadingMore: !replace);

    if (previousCancel != null) {
      await previousCancel.cancel();
    }
    if (_disposed || !identical(_activeCancel, capturedCancel)) {
      return;
    }

    try {
      final result = await capturedCancel.run<T>(load(params));
      if (_disposed || !identical(_activeCancel, capturedCancel)) return;
      if (result == null) return; // cancelled

      _errorNotifier.value = null;
      _lastResult = result;
      onLoadSuccess(result, params, replace: replace);
    } catch (e) {
      if (!_disposed && identical(_activeCancel, capturedCancel)) {
        _errorNotifier.value = e;
      }
      rethrow;
    } finally {
      if (!_disposed && identical(_activeCancel, capturedCancel)) {
        _setLoading(reloading: false, loadingMore: false);
      }
    }
  }

  /// Applies a successful loader [result] to the collection.
  ///
  /// Invoked by [runLoad] after [lastResult] has been committed. The
  /// subclass replaces (`replace == true`) or appends (`replace == false`)
  /// the collection, recomputes/sets [hasMore] and calls [notifyListeners].
  /// [params] is provided for subclasses that derive `hasMore` from the
  /// request (offset pagination); page-model subclasses ignore it.
  @protected
  void onLoadSuccess(T result, Params params, {required bool replace});

  /// Handles a `minLength` rejection from [searchStrategy] in [reload].
  ///
  /// Invoked after [isLoading] has been reset to `false`. The subclass
  /// clears the collection, sets `hasMore = false` and calls
  /// [notifyListeners] only when the collection was non-empty (i.e. it
  /// actually changed).
  @protected
  void onLoadRejected();

  /// Whether the dispatcher has been disposed.
  ///
  /// Exposed for subclass mutators (e.g. `mutate`) that must become no-ops
  /// after [dispose].
  @protected
  bool get isDisposed => _disposed;
}
