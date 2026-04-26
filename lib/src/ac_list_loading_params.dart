/// Base contract for loading parameters accepted by the list dispatcher.
///
/// A user-defined parameters type (passed to `reload` and `loadMore`) must
/// mix in this base mixin. For offset-based pagination, additionally mix in
/// [ACOffsetParamsMixin]. For cursor-based pagination (or any other custom
/// pagination scheme), declare your own field on the params class — the
/// dispatcher does not read pagination fields itself; they are meant for
/// the loader when building a request.
///
/// The base mixin carries two fields:
/// - [limit] — informational, not used by the dispatcher (it is meant for
///   the loader itself when building a request);
/// - [query] — read by the dispatcher for `ACSearchStrategy` (debounce,
///   minLength, reset on empty value).
///
/// The mixin contains no logic: it only declares getters.
mixin ACParamsMixin {
  /// Maximum number of items the loader is expected to return.
  ///
  /// Informational field: the dispatcher does not read it. A value `>= 0`
  /// is recommended; validation is up to the consumer.
  int? get limit;

  /// Search query; the basis for `ACSearchStrategy` behaviour.
  ///
  /// The dispatcher treats `null` and an empty string equivalently — as
  /// the absence of a search query. Trimming whitespace is the
  /// consumer's responsibility.
  String? get query;
}

/// Offset pagination parameters.
///
/// Built on top of [ACParamsMixin] by adding the [offset]
/// field — the offset of the first requested record. The dispatcher does
/// not read this field; it is intended for the loader when building a
/// request to the data source.
///
/// Typical usage:
///
/// ```dart
/// final class UserListParams
///     with ACParamsMixin, ACOffsetParamsMixin {
///   const UserListParams({this.offset, this.limit, this.query});
///
///   @override
///   final int? offset;
///   @override
///   final int? limit;
///   @override
///   final String? query;
/// }
/// ```
///
/// For cursor-based pagination, declare your own `cursor` field on the
/// params class with [ACParamsMixin] alone — no dedicated mixin is
/// required. To carry the next-page cursor returned by the server, use
/// `dispatcher.lastResult?.<your_cursor_field>` after a successful load.
mixin ACOffsetParamsMixin on ACParamsMixin {
  /// Offset for offset-based pagination.
  ///
  /// Informational field: the dispatcher does not read it. A value `>= 0`
  /// is recommended; validation is up to the consumer.
  int? get offset;
}
