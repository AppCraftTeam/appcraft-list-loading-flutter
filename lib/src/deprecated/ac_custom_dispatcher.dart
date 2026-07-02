import '../ac_params.dart';
import 'ac_dispatcher.dart';
import 'ac_result.dart';
import 'ac_result_parser.dart';

/// Facade dispatcher for DTOs that mix in [ACResult].
///
/// Uses [ACResultParser] — items and `hasMore` are taken
/// from the corresponding getters on the result.
///
/// Example:
///
/// ```dart
/// final dispatcher =
///     ACCustomDispatcher<UserCursorParams, UserPage, User>();
/// await dispatcher.reload(
///   params: const UserCursorParams(cursor: null),
///   load: (p) => api.fetchUsers(cursor: p.cursor),
/// );
/// ```
///
/// **Extension point**: can be extended to customize loading behavior.
/// Overrides of `notifyListeners`, `dispose`, or internal state mutation
/// must respect the `ChangeNotifier` contract; `super.dispose()` is
/// required.
//
// This deprecated facade intentionally builds on the deprecated
// [ACDispatcher], [ACResult] and [ACResultParser] to preserve 0.2.0
// behaviour parity until removal in 1.0.0.
@Deprecated(
  'Will be removed in 1.0.0. Use ACListDispatcher (offset) or '
  'ACPageDispatcher (ACPage DTO).',
)
class ACCustomDispatcher<
        P extends ACParamsMixin,
        // ignore: deprecated_member_use_from_same_package
        R extends ACResult<T>,
        // ignore: deprecated_member_use_from_same_package
        T> extends ACDispatcher<P, R, T> {
  /// Creates a dispatcher with [ACResultParser] and an
  /// optional [searchStrategy].
  ACCustomDispatcher({
    super.searchStrategy,
  }) : super(
          // ignore: deprecated_member_use_from_same_package
          parser: ACResultParser<P, R, T>(),
        );
}
