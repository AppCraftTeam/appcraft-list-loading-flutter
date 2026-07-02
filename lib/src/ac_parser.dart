import 'ac_params.dart';
import 'ac_result.dart';

/// Strategy for extracting items and the `hasMore` flag from the loader
/// result.
///
/// The parser allows the dispatcher to work with an arbitrary response
/// type [R] without requiring it to be wrapped in [ACResult].
/// This is useful when the source returns a plain list (`List<T>`) or a
/// DTO with its own field schema.
///
/// Contract:
/// - [extractItems] must return the items of the current page without
///   side effects. For `reload` the dispatcher replaces the accumulated
///   list with the result; for `loadMore` it appends to the end.
/// - [hasMore] synchronously computes whether a next page is available
///   from the result and/or the passed parameters. Exceptions thrown by
///   parser methods propagate out of `reload`/`loadMore`.
abstract class ACParser<P extends ACParamsMixin, R, T> {
  /// Const constructor so that subclasses can declare `const` instances.
  const ACParser();

  /// Extracts the items of the current page from [result].
  List<T> extractItems(P params, R result);

  /// Determines whether more pages are available to load.
  bool hasMore(P params, R result);
}

/// Parser for DTOs that mix in [ACResult].
///
/// Delegates both methods directly to the result getters: [extractItems]
/// returns `result.items`, [hasMore] returns `result.hasMore`.
///
/// **Extension point**: can be extended or implemented. Overrides of
/// `extractItems` and `hasMore` must remain side-effect free and
/// synchronous, and continue to honor the [ACResult] contract
/// of the result type [R].
class ACResultParser<
    P extends ACParamsMixin,
    R extends ACResult<T>,
    T> implements ACParser<P, R, T> {
  /// Creates a parser. The instance can be declared as `const`.
  const ACResultParser();

  @override
  List<T> extractItems(P params, R result) => result.items;

  @override
  bool hasMore(P params, R result) => result.hasMore;
}
