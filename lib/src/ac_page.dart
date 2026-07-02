/// Contract for a loaded list page.
///
/// A user response DTO mixes in this mixin and implements the two getters.
/// `ACPageDispatcher` reads [items] and [hasMore] directly from the model —
/// a separate parser callback is not required.
///
/// This is the replacement for the deprecated `ACResult`: the member set is
/// identical, only the name conveys the "page" semantics used by
/// `ACPageDispatcher` (`R extends ACPage<T>`).
mixin ACPage<T> {
  /// Items received on this page.
  List<T> get items;

  /// Whether there are more pages to load via `loadMore`.
  bool get hasMore;
}
