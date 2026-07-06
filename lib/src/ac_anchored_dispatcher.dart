import 'package:flutter/foundation.dart';

import 'ac_anchored_page.dart';
import 'ac_cancel_strategy.dart';
import 'ac_page.dart';
import 'ac_page_dispatcher.dart';
import 'ac_params.dart';

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
/// - [itemsOlder] grows «into the past»: `loadOlder` appends closest-older →
///   oldest.
/// - [itemsNewer] grows «into the future»: it is seeded by `loadAround` and
///   extended by `loadNewer` (anchor → newest).
/// - [items] is the merged, read-only view `reverse(itemsOlder) ++ itemsNewer`.
///
/// Cursors are managed manually by the consumer: the initial cursors come from
/// [lastAround], and subsequent ones from [lastResultOlder]/[lastResultNewer].
/// The `searchStrategy` of the per-side dispatchers is **not** applied — this
/// dispatcher only uses `loadMore`.
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
  }

  final ACPageDispatcher<P, R, T> _older = ACPageDispatcher<P, R, T>();
  final ACPageDispatcher<P, R, T> _newer = ACPageDispatcher<P, R, T>();

  bool _disposed = false;
  ACCancelStrategy? _aroundCancel;
  final ValueNotifier<bool> _aroundLoading = ValueNotifier<bool>(false);
  final ValueNotifier<Object?> _aroundError = ValueNotifier<Object?>(null);
  ACAnchoredPage<T>? _lastAround;

  /// Forwards a side's item-change notification, unless disposed.
  void _onSide() {
    if (!_disposed) notifyListeners();
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
  bool get hasMoreOlder => _older.hasMore;

  /// Manually sets the older side's next-page flag (guard for [loadOlder]).
  set hasMoreOlder(bool value) => _older.hasMore = value;

  /// Whether more newer items can be loaded via [loadNewer].
  bool get hasMoreNewer => _newer.hasMore;

  /// Manually sets the newer side's next-page flag (guard for [loadNewer]).
  set hasMoreNewer(bool value) => _newer.hasMore = value;

  /// Whether an older-side load is in progress.
  bool get isLoadingOlder => _older.isLoading;

  /// Whether a newer-side load is in progress.
  bool get isLoadingNewer => _newer.isLoading;

  /// Whether an around-load is in progress.
  bool get isLoadingAround => _aroundLoading.value;

  /// Reactive channel mirroring [isLoadingOlder].
  ValueListenable<bool> get loadingOlderListenable => _older.loadingListenable;

  /// Reactive channel mirroring [isLoadingNewer].
  ValueListenable<bool> get loadingNewerListenable => _newer.loadingListenable;

  /// Reactive channel mirroring [isLoadingAround].
  ValueListenable<bool> get loadingAroundListenable => _aroundLoading;

  /// The last page returned by [loadOlder], or `null`.
  R? get lastResultOlder => _older.lastResult;

  /// The last page returned by [loadNewer], or `null`.
  ///
  /// `null` right after a [loadAround] (the newer side was seeded, not loaded)
  /// — read the initial cursors from [lastAround] in that case.
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
    _older.dispose();
    _newer.dispose();
    _aroundLoading.dispose();
    _aroundError.dispose();
    _aroundCancel?.cancel().ignore();

    super.dispose();
  }
}
