import '../ac_params.dart';
import '../ac_parser.dart';

/// Parser for offset pagination: the loader returns a plain `List<T>`.
///
/// `hasMore` is computed as `result.length >= params.limit`. If
/// [ACParamsMixin.limit] is `null`, the source is assumed to
/// have no limit and pages may continue indefinitely (`hasMore == true`).
///
/// **Extension point**: can be extended or implemented. Overrides of
/// `extractItems` and `hasMore` must remain side-effect free and
/// synchronous.
@Deprecated(
  'Будет удалён в 1.0.0. Используйте ACListDispatcher — логика hasMore '
  'встроена, отдельный parser не нужен.',
)
class ACDefaultParser<
    P extends ACOffsetParamsMixin, T>
    implements ACParser<P, List<T>, T> {
  /// Creates a parser. The instance can be declared as `const`.
  const ACDefaultParser();

  @override
  List<T> extractItems(P params, List<T> result) => result;

  @override
  bool hasMore(P params, List<T> result) {
    final limit = params.limit;
    if (limit == null) return true;
    return result.length >= limit;
  }
}
