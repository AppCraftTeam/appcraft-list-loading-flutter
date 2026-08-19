import 'package:flutter/foundation.dart';

import 'ac_anchored_page.dart';
import 'ac_cancel_strategy.dart';
import 'ac_page.dart';
import 'ac_page_dispatcher.dart';
import 'ac_params.dart';
import 'ac_search_debouncer.dart';

/// Bidirectional, anchor-centred paginating dispatcher.
///
/// Loads a list **around** an anchor and then grows independently in both
/// directions: back in time (older) and forward in time (newer). It is built
/// as a **composition of two** [ACPageDispatcher]s — `_older` and `_newer` —
/// so each side reuses the full loading engine (cancellation, staleness
/// guards, `isLoading`, `lastResult`, error channels, `retry`, `mutate`)
/// while this class only orchestrates the anchor load and exposes a merged
/// list view.
///
/// Layout of the merged [items]:
///
/// ```text
/// oldest … ← itemsOlder (reversed) …  ANCHOR  … itemsNewer → … newest
/// ```
///
/// - [itemsOlder] is seeded by [reloadOlder] and grows «into the past»:
///   `loadOlder` appends closest-older → oldest.
/// - [itemsNewer] is seeded by [reloadNewer] and grows «into the future»:
///   `loadNewer` appends anchor → newest. The anchor belongs to this side.
/// - [items] is the merged, read-only view `reverse(itemsOlder) ++ itemsNewer`.
///
/// A window around an anchor is composed by the **caller** out of two
/// independent seeds — [reloadOlder] and [reloadNewer] — in whatever order,
/// sequentially or concurrently, over one request or two. The dispatcher does
/// not couple them: it knows nothing about cursors or the server's shape, and
/// leaves the request count, the concurrency and the handling of a one-sided
/// failure to the caller.
///
/// Cursors are managed manually by the consumer and are read uniformly from
/// [lastResultOlder]/[lastResultNewer] — both the initial ones (committed by
/// the seeds) and the subsequent ones.
///
/// The per-side `searchStrategy` is neutralised (no debounce, no `minLength`
/// gate): search is not a concept here, and the seeds must never be delayed
/// or turned into a silent clear by the query carried in `params`.
///
/// Notifications: the dispatcher extends [ChangeNotifier] and forwards a
/// notification whenever **either side's items change** (subscribed via the
/// sides' own `notifyListeners`). Changing only the loading flags or the
/// `hasMore` flags does not notify; drive spinners via the per-side
/// listenables instead.
///
/// Generic parameters:
/// - [P] — the loading parameters type mixing in [ACParamsMixin];
/// - [R] — the per-side page model returned by `loadOlder`/`loadNewer`,
///   mixing in [ACPage];
/// - [T] — the list element type.
final class ACAnchoredDispatcher<P extends ACParamsMixin,
    R extends ACPage<T>, T> extends ChangeNotifier {
  /// Creates an anchored dispatcher with two fresh, empty sides.
  ///
  /// Both sides start empty with `hasMore == false`; nothing loads until
  /// [loadAround], [loadOlder] or [loadNewer] is called.
  ACAnchoredDispatcher() {
    _older.addListener(_onSide);
    _newer.addListener(_onSide);
    _older.reloadingListenable.addListener(_onReloading);
    _newer.reloadingListenable.addListener(_onReloading);
    _older.errorListenable.addListener(_onError);
    _newer.errorListenable.addListener(_onError);
  }

  // Both sides are built with a neutralised search strategy. `reloadOlder` /
  // `reloadNewer` go through `ACPageDispatcher.reload`, which gates on
  // `searchStrategy.schedule(params.query)`; with the default debouncer a
  // non-empty query shorter than `minLength` would be treated as a rejection
  // and **clear the side without loading**, and a longer one would be delayed
  // by 300ms. Search is not a concept for an anchored feed, so the gate is
  // disarmed rather than left to surprise the caller.
  final ACPageDispatcher<P, R, T> _older = ACPageDispatcher<P, R, T>(
    searchStrategy: ACSearchDebouncer(
      debounce: Duration.zero,
      minLength: 0,
    ),
  );
  final ACPageDispatcher<P, R, T> _newer = ACPageDispatcher<P, R, T>(
    searchStrategy: ACSearchDebouncer(
      debounce: Duration.zero,
      minLength: 0,
    ),
  );

  bool _disposed = false;
  ACCancelStrategy? _aroundCancel;
  final ValueNotifier<bool> _aroundLoading = ValueNotifier<bool>(false);
  final ValueNotifier<Object?> _aroundError = ValueNotifier<Object?>(null);
  ACAnchoredPage<T>? _lastAround;
  final ValueNotifier<bool> _reloadingAny = ValueNotifier<bool>(false);
  final ValueNotifier<Object?> _errorAny = ValueNotifier<Object?>(null);

  /// Forwards a side's item-change notification, unless disposed.
  void _onSide() {
    if (!_disposed) notifyListeners();
  }

  /// Recomputes [isReloadingAny] from both sides' reload flags.
  ///
  /// Subscribed to each side's `reloadingListenable` rather than its
  /// `loadingListenable`: the latter carries the derived
  /// `reloading || loadingMore` and stays silent when a seed starts on top of
  /// an in-flight edge load, which would leave this channel out of sync with
  /// the [isReloadingAny] getter.
  void _onReloading() {
    if (!_disposed) _reloadingAny.value = isReloadingAny;
  }

  /// Recomputes [lastErrorAny] from both sides' error channels.
  void _onError() {
    if (!_disposed) _errorAny.value = lastErrorAny;
  }

  // ---------------------------------------------------------------------------
  // List views
  // ---------------------------------------------------------------------------

  /// Unmodifiable view of the older side (closest-older → oldest).
  List<T> get itemsOlder => _older.items;

  /// Unmodifiable view of the newer side (anchor → newest).
  List<T> get itemsNewer => _newer.items;

  /// Unmodifiable merged view `reverse(itemsOlder) ++ itemsNewer`.
  ///
  /// Reversing the older side restores natural chronological order
  /// (oldest → anchor → newest). Attempting to mutate the returned list
  /// throws `UnsupportedError`.
  List<T> get items => List<T>.unmodifiable(<T>[
        ..._older.items.reversed,
        ..._newer.items,
      ]);

  // ---------------------------------------------------------------------------
  // Loading
  // ---------------------------------------------------------------------------

  /// Loads the initial window around an anchor.
  ///
  /// Runs its own orchestration (independent of the per-side engines): it
  /// cancels any previous around-load and **both** sides, applies a staleness
  /// guard, and on success seeds the central [ACAnchoredPage.items] into the
  /// newer side, clears the older side and applies both `hasMore` flags via
  /// the side setters. The central page is stored in [lastAround].
  ///
  /// Seeding goes through the sides' `mutate`, so the merged-list notification
  /// is forwarded automatically. After an around-load [lastResultNewer] is
  /// `null` (the side was seeded, not loaded) — read the initial cursors from
  /// [lastAround].
  ///
  /// Loader exceptions are **propagated outside** and stored in
  /// [lastErrorAround]; the [isLoadingAround] flag is reset via `try/finally`.
  /// A result that arrives after [dispose] or after a newer around-load has
  /// started is ignored (stale) and does not write state.
  ///
  /// [cancelStrategy] — an optional cancellation strategy for this load;
  /// otherwise a fresh [ACOperationCancelStrategy] is used. A no-op after
  /// [dispose].
  Future<void> loadAround({
    required P params,
    required Future<ACAnchoredPage<T>> Function(P params) load,
    ACCancelStrategy? cancelStrategy,
  }) async {
    if (_disposed) return;

    final previous = _aroundCancel;
    final captured = cancelStrategy ?? ACOperationCancelStrategy();
    _aroundCancel = captured;
    _aroundLoading.value = true;

    await _older.cancel();
    await _newer.cancel();
    await previous?.cancel();
    if (_disposed || !identical(_aroundCancel, captured)) return;

    try {
      final page = await captured.run<ACAnchoredPage<T>>(load(params));
      if (_disposed || !identical(_aroundCancel, captured)) return;
      if (page == null) return; // cancelled

      _aroundError.value = null;
      _newer.mutate((l) => l
        ..clear()
        ..addAll(page.items));
      _newer.hasMore = page.hasMoreNewer;
      _older.mutate((l) => l.clear());
      _older.hasMore = page.hasMoreOlder;
      _lastAround = page;
    } catch (e) {
      if (!_disposed && identical(_aroundCancel, captured)) {
        _aroundError.value = e;
      }
      rethrow;
    } finally {
      if (!_disposed && identical(_aroundCancel, captured)) {
        _aroundLoading.value = false;
      }
    }
  }

  /// Seeds the older side with a single page — the «older half» of a window
  /// around an anchor.
  ///
  /// Delegates to the older side's `reload`: the side's items are **replaced**
  /// by `page.items` (not appended), [hasMoreOlder] is read from
  /// `page.hasMore`, [lastResultOlder] is committed and the merged-list
  /// notification is forwarded. Any in-flight load on the older side is
  /// cancelled first, and its late result is discarded as stale.
  ///
  /// The page's items must be ordered **closest-older → oldest** — the same
  /// order in which [loadOlder] grows the side. Nothing is reversed inside the
  /// package: if the server returns history chronologically, the caller
  /// reverses it. [items] then reads `reverse(itemsOlder) ++ itemsNewer`, i.e.
  /// oldest → newest.
  ///
  /// Independent of the newer side: this call leaves its items, its
  /// [hasMoreNewer] flag and its loading state untouched. Building a window
  /// around an anchor therefore means calling this **and** [reloadNewer] —
  /// in whatever order, sequentially or concurrently, over one request or
  /// two. The dispatcher does not couple the two calls: how many requests a
  /// window costs, and what happens when only one of the two sides fails,
  /// are the caller's decisions.
  ///
  /// Loader exceptions are **propagated outside** and stored in
  /// [lastErrorOlder]; [isLoadingOlder] is reset via `try/finally`. A
  /// successful seed clears [lastErrorOlder]. The call is captured as the
  /// side's last operation, so a subsequent [retryOlder] repeats this seed.
  ///
  /// [cancelStrategy] — an optional cancellation strategy for this load;
  /// otherwise a fresh [ACOperationCancelStrategy] is used. A no-op after
  /// [dispose].
  Future<void> reloadOlder({
    required P params,
    required Future<R> Function(P params) load,
    ACCancelStrategy? cancelStrategy,
  }) =>
      _older.reload(
        params: params,
        load: load,
        cancelStrategy: cancelStrategy,
      );

  /// Seeds the newer side with a single page — the anchor and the «newer
  /// half» of a window around it.
  ///
  /// Mirrors [reloadOlder] on the newer side: items are **replaced** by
  /// `page.items`, [hasMoreNewer] is read from `page.hasMore`,
  /// [lastResultNewer] is committed, the in-flight load on this side is
  /// cancelled and its late result discarded.
  ///
  /// The page's items must be ordered **anchor → newest** — the same order in
  /// which [loadNewer] grows the side. The anchor itself belongs to this side.
  ///
  /// Independent of the older side; see [reloadOlder] for the caller's
  /// responsibilities when composing a window from both calls.
  ///
  /// Loader exceptions are **propagated outside** and stored in
  /// [lastErrorNewer]; [isLoadingNewer] is reset via `try/finally`. The call
  /// is captured as the side's last operation, so a subsequent [retryNewer]
  /// repeats this seed.
  ///
  /// [cancelStrategy] — an optional cancellation strategy for this load;
  /// otherwise a fresh [ACOperationCancelStrategy] is used. A no-op after
  /// [dispose].
  Future<void> reloadNewer({
    required P params,
    required Future<R> Function(P params) load,
    ACCancelStrategy? cancelStrategy,
  }) =>
      _newer.reload(
        params: params,
        load: load,
        cancelStrategy: cancelStrategy,
      );

  /// Loads the next older page, appending to [itemsOlder].
  ///
  /// Delegates to the older side's `loadMore`: guards `!hasMoreOlder` /
  /// `isLoadingOlder` apply, and [force] bypasses **only** the `!hasMoreOlder`
  /// guard. Independent of the newer side.
  Future<void> loadOlder({
    required P params,
    required Future<R> Function(P params) load,
    ACCancelStrategy? cancelStrategy,
    bool force = false,
  }) =>
      _older.loadMore(
        params: params,
        load: load,
        cancelStrategy: cancelStrategy,
        force: force,
      );

  /// Loads the next newer page, appending to [itemsNewer].
  ///
  /// Delegates to the newer side's `loadMore`: guards `!hasMoreNewer` /
  /// `isLoadingNewer` apply, and [force] bypasses **only** the `!hasMoreNewer`
  /// guard. Independent of the older side.
  Future<void> loadNewer({
    required P params,
    required Future<R> Function(P params) load,
    ACCancelStrategy? cancelStrategy,
    bool force = false,
  }) =>
      _newer.loadMore(
        params: params,
        load: load,
        cancelStrategy: cancelStrategy,
        force: force,
      );

  // ---------------------------------------------------------------------------
  // Per-side state (delegated)
  // ---------------------------------------------------------------------------

  /// Whether more older items can be loaded via [loadOlder].
  ///
  /// After [reloadOlder] this is read from the seed page's `hasMore` and
  /// describes what lies **beyond** the window's older edge, not what the
  /// window itself contains.
  bool get hasMoreOlder => _older.hasMore;

  /// Manually sets the older side's next-page flag (guard for [loadOlder]).
  set hasMoreOlder(bool value) => _older.hasMore = value;

  /// Whether more newer items can be loaded via [loadNewer].
  ///
  /// After [reloadNewer] this is read from the seed page's `hasMore` and
  /// describes what lies **beyond** the window's newer edge, not what the
  /// window itself contains.
  bool get hasMoreNewer => _newer.hasMore;

  /// Manually sets the newer side's next-page flag (guard for [loadNewer]).
  set hasMoreNewer(bool value) => _newer.hasMore = value;

  /// Whether an older-side load is in progress.
  bool get isLoadingOlder => _older.isLoading;

  /// Whether a newer-side load is in progress.
  bool get isLoadingNewer => _newer.isLoading;

  /// Whether an around-load is in progress.
  bool get isLoadingAround => _aroundLoading.value;

  /// Whether a **seed** ([reloadOlder] or [reloadNewer]) is running on either
  /// side.
  ///
  /// Deliberately blind to [loadOlder] / [loadNewer]: it answers «is the
  /// window still being built», which is what an initial-load spinner needs.
  /// Edge spinners are driven by [loadingOlderListenable] /
  /// [loadingNewerListenable] instead.
  bool get isReloadingAny => _older.isReloading || _newer.isReloading;

  /// Reactive channel mirroring [isReloadingAny].
  ///
  /// Independent of the `notifyListeners` contract: a change here does not
  /// notify the dispatcher's own subscribers. Released by [dispose].
  ValueListenable<bool> get reloadingAnyListenable => _reloadingAny;

  /// The last error held by either side, or `null` when both are clear.
  ///
  /// Equals `lastErrorOlder ?? lastErrorNewer`: it stays non-`null` while **at
  /// least one** side holds an error, so a success on one side cannot hide a
  /// failure on the other. When both sides hold an error the older one wins —
  /// an arbitrary but stable choice.
  ///
  /// Not split by operation kind: the per-side error channel does not
  /// distinguish a seed from an edge load either. For a targeted reaction use
  /// [lastErrorOlder] / [lastErrorNewer] with [retryOlder] / [retryNewer].
  Object? get lastErrorAny => _older.lastError ?? _newer.lastError;

  /// Reactive channel mirroring [lastErrorAny].
  ///
  /// Independent of the `notifyListeners` contract. Released by [dispose].
  ValueListenable<Object?> get errorAnyListenable => _errorAny;

  /// Reactive channel mirroring [isLoadingOlder].
  ValueListenable<bool> get loadingOlderListenable => _older.loadingListenable;

  /// Reactive channel mirroring [isLoadingNewer].
  ValueListenable<bool> get loadingNewerListenable => _newer.loadingListenable;

  /// Reactive channel mirroring [isLoadingAround].
  ValueListenable<bool> get loadingAroundListenable => _aroundLoading;

  /// The last page returned by [reloadOlder] or [loadOlder], or `null`.
  ///
  /// Committed by the seed as well as by every edge load, so the initial
  /// cursor and the subsequent ones are read from this same member.
  R? get lastResultOlder => _older.lastResult;

  /// The last page returned by [reloadNewer] or [loadNewer], or `null`.
  ///
  /// Committed by the seed as well as by every edge load, so the initial
  /// cursor and the subsequent ones are read from this same member.
  ///
  /// The one exception is the deprecated `loadAround`, which seeds the newer
  /// side without loading it and therefore leaves this `null`.
  R? get lastResultNewer => _newer.lastResult;

  /// The last around-page seeded by [loadAround], or `null`.
  ACAnchoredPage<T>? get lastAround => _lastAround;

  /// The error thrown by the last [loadOlder], or `null` if it succeeded.
  Object? get lastErrorOlder => _older.lastError;

  /// The error thrown by the last [loadNewer], or `null` if it succeeded.
  Object? get lastErrorNewer => _newer.lastError;

  /// The error thrown by the last [loadAround], or `null` if it succeeded.
  Object? get lastErrorAround => _aroundError.value;

  /// Reactive channel mirroring [lastErrorOlder].
  ValueListenable<Object?> get errorOlderListenable => _older.errorListenable;

  /// Reactive channel mirroring [lastErrorNewer].
  ValueListenable<Object?> get errorNewerListenable => _newer.errorListenable;

  /// Reactive channel mirroring [lastErrorAround].
  ValueListenable<Object?> get errorAroundListenable => _aroundError;

  /// Repeats the older side's last captured operation.
  Future<void> retryOlder() => _older.retry();

  /// Repeats the newer side's last captured operation.
  Future<void> retryNewer() => _newer.retry();

  // ---------------------------------------------------------------------------
  // Realtime mutation
  // ---------------------------------------------------------------------------

  /// Mutates the older side's items in place (single notification).
  ///
  /// The only sanctioned write path into the older side: the [update] callback
  /// receives the mutable backing list. A no-op after [dispose].
  void mutateOlder(void Function(List<T> items) update) => _older.mutate(update);

  /// Mutates the newer side's items in place (single notification).
  ///
  /// The only sanctioned write path into the newer side: the [update] callback
  /// receives the mutable backing list. A no-op after [dispose].
  void mutateNewer(void Function(List<T> items) update) => _newer.mutate(update);

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Cancels the active around-load and both sides' active loads.
  ///
  /// Does not reset any collection state. A safe no-op after [dispose].
  Future<void> cancel() async {
    if (_disposed) return;
    await _aroundCancel?.cancel();
    await _older.cancel();
    await _newer.cancel();
  }

  /// Releases both sides, the around notifiers and the around cancel strategy.
  ///
  /// Idempotent: a repeated [dispose] is a no-op. Any public method called
  /// after [dispose] becomes a no-op.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;

    _older.removeListener(_onSide);
    _newer.removeListener(_onSide);
    _older.reloadingListenable.removeListener(_onReloading);
    _newer.reloadingListenable.removeListener(_onReloading);
    _older.errorListenable.removeListener(_onError);
    _newer.errorListenable.removeListener(_onError);
    _older.dispose();
    _newer.dispose();
    _reloadingAny.dispose();
    _errorAny.dispose();
    _aroundLoading.dispose();
    _aroundError.dispose();
    _aroundCancel?.cancel().ignore();

    super.dispose();
  }
}
