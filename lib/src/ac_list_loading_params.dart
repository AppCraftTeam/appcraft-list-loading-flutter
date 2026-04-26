/// Base contract for loading parameters accepted by the list dispatcher.
///
/// A user-defined parameters type (passed to `reload` and `loadMore`) must
/// mix in one of the concrete mixins — [ACOffsetParamsMixin] for
/// offset-based pagination or [ACCursorListLoadingParamsMixin] for
/// cursor-based pagination — both built on top of this base mixin.
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
mixin ACOffsetParamsMixin on ACParamsMixin {
  /// Offset for offset-based pagination.
  ///
  /// Informational field: the dispatcher does not read it. A value `>= 0`
  /// is recommended; validation is up to the consumer.
  int? get offset;
}

/// Cursor pagination parameters.
///
/// Built on top of [ACParamsMixin] by adding the [cursor]
/// field — an opaque identifier of the next page returned by the data
/// source in its response. The dispatcher does not read this field;
/// keeping the current cursor between `reload`/`loadMore` calls is the
/// consumer's responsibility.
///
/// Typical usage:
///
/// ```dart
/// final class UserCursorParams
///     with ACParamsMixin, ACCursorListLoadingParamsMixin {
///   const UserCursorParams({this.limit, this.cursor, this.query});
///
///   @override
///   final int? limit;
///   @override
///   final String? cursor;
///   @override
///   final String? query;
/// }
/// ```
mixin ACCursorListLoadingParamsMixin on ACParamsMixin {
  /// Opaque cursor of the next page (or `null` before the first load /
  /// on the last page).
  ///
  /// Informational field: the dispatcher does not read it.
  String? get cursor;
}
