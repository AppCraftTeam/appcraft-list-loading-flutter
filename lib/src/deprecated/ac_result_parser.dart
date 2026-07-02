import '../ac_params.dart';
import 'ac_parser.dart';
import 'ac_result.dart';

/// Parser for DTOs that mix in [ACResult].
///
/// Delegates both methods directly to the result getters: [extractItems]
/// returns `result.items`, [hasMore] returns `result.hasMore`.
///
/// **Extension point**: can be extended or implemented. Overrides of
/// `extractItems` and `hasMore` must remain side-effect free and
/// synchronous, and continue to honor the [ACResult] contract
/// of the result type [R].
//
// This deprecated parser intentionally builds on the deprecated [ACParser]
// and [ACResult] to preserve 0.2.0 behaviour parity until removal in 1.0.0.
@Deprecated(
  'Will be removed in 1.0.0. Use ACPageDispatcher / self-contained '
  'dispatchers.',
)
class ACResultParser<
    P extends ACParamsMixin,
    // ignore: deprecated_member_use_from_same_package
    R extends ACResult<T>,
    // ignore: deprecated_member_use_from_same_package
    T> implements ACParser<P, R, T> {
  /// Creates a parser. The instance can be declared as `const`.
  const ACResultParser();

  @override
  List<T> extractItems(P params, R result) => result.items;

  @override
  bool hasMore(P params, R result) => result.hasMore;
}
