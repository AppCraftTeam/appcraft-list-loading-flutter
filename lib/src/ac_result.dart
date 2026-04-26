/// Contract for the result of loading a list page.
///
/// User response DTOs mix in this mixin and implement the two getters.
/// The dispatcher reads [items] and [hasMore] directly — a separate
/// parser callback is not required.
mixin ACResult<T> {
  /// Items received on this page.
  List<T> get items;

  /// Whether there are more pages to load via `loadMore`.
  bool get hasMore;
}
