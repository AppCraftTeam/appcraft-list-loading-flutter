/// Page model for the deprecated `ACAnchoredDispatcher.loadAround`.
///
/// **Despite its name, this model cannot express a window around an anchor.**
/// It carries a single list, which `loadAround` seeds verbatim into the
/// **newer** side while clearing the older one — so after an around-load the
/// older side is always empty, whatever the loader returned. The two
/// directional flags are applied to their respective sides, but only the
/// newer side ever receives items.
///
/// Deprecated together with `loadAround`. To build an actual window around an
/// anchor, seed each side separately with a plain `ACPage`:
///
/// ```dart
/// await dispatcher.reloadOlder(params: p, load: loadHistory); // closest-older -> oldest
/// await dispatcher.reloadNewer(params: p, load: loadFeed);    // anchor -> newest
/// ```
///
/// Each side's `hasMore` then comes from its own page and describes what lies
/// beyond that side's edge. How many requests a window costs, and whether the
/// two seeds run sequentially or concurrently, is up to the caller.
///
/// Type parameter:
/// - [T] — the list element type.
@Deprecated(
  'Cannot express a window around an anchor: loadAround always clears the '
  'older side. Seed each side with ACPage via reloadOlder/reloadNewer. '
  'Will be removed in 2.0.0.',
)
mixin ACAnchoredPage<T> {
  /// The items fetched from the anchor forward, in reading order
  /// `anchor → newer`. Seeded verbatim into the newer side.
  ///
  /// There is no field for the older half of a window — this is the modelling
  /// gap that makes an around-load one-sided.
  List<T> get items;

  /// Whether more items exist **older** than the fetched page. Applied to the
  /// older side's `hasMore`, even though that side receives no items.
  bool get hasMoreOlder;

  /// Whether more items exist **newer** than the fetched page. Applied to the
  /// newer side's `hasMore`.
  bool get hasMoreNewer;
}
