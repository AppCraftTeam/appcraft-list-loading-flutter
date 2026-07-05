import 'ac_loading_dispatcher.dart';
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
/// The loading lifecycle (`reload`, `loadMore`, `cancel`, `dispose`,
/// [isLoading], [lastResult]) is inherited from [ACLoadingDispatcher]; this
/// class only supplies the collection state and the extension points
/// ([onLoadSuccess], [onLoadRejected], [hasMore]). The loader result type is
/// bound to [R], so [lastResult] is inherited as `R?` (access to extra page
/// fields — e.g. a next cursor — without a cast).
///
/// The dispatcher extends `ChangeNotifier` via [ACLoadingDispatcher]. State
/// is exposed via the [items], [isLoading] and [hasMore] getters;
/// `notifyListeners` is invoked only when **[items] change** — subscribers
/// re-read `items` and update the UI on their own. Changes to [isLoading] or
/// [hasMore] without a change in [items] do not trigger a notification; if a
/// consumer needs a spinner, [isLoading] can be read synchronously
/// before/after `reload`/`loadMore` (for example by wrapping the call in
/// `setState`).
///
/// Generic parameters:
/// - [P] — the loading parameters type mixing in [ACParamsMixin];
/// - [R] — the page model returned by the loader, mixing in [ACPage];
/// - [T] — the list element type.
///
/// Search behaviour is configured via `searchStrategy` and applies only
/// in `reload`: debounce for a changed query, rejection when `minLength`
/// is not met (with items cleared), immediate launch for an empty or
/// matching query. In `loadMore` the search strategy is ignored: the
/// query from params is passed to the loader as-is, debounce and the
/// minLength check are not applied.
///
/// Loader errors are **not** caught: an exception thrown inside
/// `load(params)` propagates out of `reload`/`loadMore`. The
/// [isLoading] flag is guaranteed to be reset (via `try/finally`).
class ACPageDispatcher<P extends ACParamsMixin, R extends ACPage<T>, T>
    extends ACLoadingDispatcher<P, R> {
  /// Creates a dispatcher with an optional [searchStrategy].
  ///
  /// If [searchStrategy] is not provided, an [ACDebouncedSearchStrategy]
  /// with defaults is used (debounce `300ms`, `minLength = 3`). The
  /// strategy is set once and does not change afterwards.
  ACPageDispatcher({
    super.searchStrategy,
  });

  final List<T> _items = <T>[];
  bool _hasMore = true;

  /// Unmodifiable view of the accumulated items.
  ///
  /// Returned via `List.unmodifiable` — attempting to mutate it from
  /// the outside throws `UnsupportedError`.
  List<T> get items => List<T>.unmodifiable(_items);

  /// Whether there are more items to load via [loadMore].
  ///
  /// Read synchronously; `notifyListeners` is **not** invoked when this
  /// flag changes without a change in [items].
  @override
  bool get hasMore => _hasMore;

  /// Manually sets the next-page flag.
  ///
  /// Overrides the `hasMore` value read from the last loaded page. It acts
  /// as the guard for [loadMore]: when set to `false`, subsequent
  /// [loadMore] calls are ignored; when set to `true`, [loadMore] may run
  /// again. `notifyListeners` is **not** invoked (parity with the loading
  /// flags: changing `hasMore` does not notify subscribers). Setting this
  /// flag does not cancel an active load.
  set hasMore(bool value) => _hasMore = value;

  /// Mutates the accumulated items in place.
  ///
  /// This is the **only sanctioned write path** into the internal list:
  /// the [items] getter returns a `List.unmodifiable` view, so external
  /// code cannot mutate the accumulated items directly. The [update]
  /// callback receives the **mutable** backing list and may perform any
  /// number of changes (add, remove, reorder, replace); all of them are
  /// batched into a **single** `notifyListeners` call emitted on success.
  ///
  /// After [dispose] this is a no-op: the callback is not invoked and no
  /// notification is emitted.
  ///
  /// If [update] throws, the exception is **propagated outside** and
  /// `notifyListeners` is **not** invoked; there is no rollback of the
  /// changes applied before the throw.
  ///
  /// [mutate] does not cancel an active load: an in-flight [reload] will
  /// overwrite the mutated items when it resolves. To seed the list
  /// before a load, call [cancel] first.
  void mutate(void Function(List<T> items) update) {
    if (isDisposed) return;
    update(_items);
    notifyListeners();
  }

  /// Applies a successful page-model [result] to the accumulated items.
  ///
  /// When `replace` is `true` the items are replaced with `result.items`;
  /// otherwise they are appended (loadMore). `hasMore` is read directly
  /// from the page model (`result.hasMore`). [params] is ignored — page
  /// pagination does not depend on the request. [notifyListeners] is
  /// invoked because [items] change.
  @override
  void onLoadSuccess(R result, P params, {required bool replace}) {
    final newItems = result.items;
    _hasMore = result.hasMore;

    if (replace) {
      _items
        ..clear()
        ..addAll(newItems);
    } else {
      _items.addAll(newItems);
    }
    notifyListeners();
  }

  /// Clears the items on a `minLength` rejection in [reload].
  ///
  /// Sets `hasMore = false` and invokes [notifyListeners] only when the
  /// list was non-empty (i.e. [items] actually changed).
  @override
  void onLoadRejected() {
    final wasNonEmpty = _items.isNotEmpty;
    _items.clear();
    _hasMore = false;
    if (wasNonEmpty) notifyListeners();
  }
}
