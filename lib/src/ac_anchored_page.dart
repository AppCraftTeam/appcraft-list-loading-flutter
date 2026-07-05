/// Around-page model for a single `loadAround` load.
///
/// Unlike the per-side `ACPage` (whose `hasMore` describes «is there more on
/// **this** side»), an around-load fetches the items centred on an anchor and
/// therefore carries **both** directional flags at once: whether more items
/// exist above the anchor (older) and below it (newer).
///
/// It is consumed by `ACAnchoredDispatcher.loadAround`, which seeds the
/// central page into the newer side and applies both `hasMore` flags to the
/// respective sides. The per-side `loadOlder`/`loadNewer` continue to use the
/// existing `ACPage` model.
///
/// Type parameter:
/// - [T] — the list element type.
///
/// Mix this into a page DTO returned by the around-loader:
///
/// ```dart
/// class MyAroundPage<T> with ACAnchoredPage<T> {
///   const MyAroundPage(this.items, this.hasMoreOlder, this.hasMoreNewer);
///   @override final List<T> items;
///   @override final bool hasMoreOlder;
///   @override final bool hasMoreNewer;
/// }
/// ```
mixin ACAnchoredPage<T> {
  /// The items fetched around the anchor, in newest-to-oldest reading order
  /// of the newer side (anchor → newer). Seeded verbatim into the newer side.
  List<T> get items;

  /// Whether more items exist **older** than the fetched window (above the
  /// anchor). Applied to the older side's `hasMore`.
  bool get hasMoreOlder;

  /// Whether more items exist **newer** than the fetched window (below the
  /// anchor). Applied to the newer side's `hasMore`.
  bool get hasMoreNewer;
}
