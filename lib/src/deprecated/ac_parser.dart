import '../ac_params.dart';
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
@Deprecated(
  'Will be removed in 1.0.0. Use ACPageDispatcher / self-contained '
  'dispatchers.',
)
abstract class ACParser<P extends ACParamsMixin, R, T> {
  /// Const constructor so that subclasses can declare `const` instances.
  const ACParser();

  /// Extracts the items of the current page from [result].
  List<T> extractItems(P params, R result);

  /// Determines whether more pages are available to load.
  bool hasMore(P params, R result);
}
