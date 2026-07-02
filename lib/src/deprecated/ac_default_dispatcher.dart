import '../ac_dispatcher.dart';
import '../ac_params.dart';
import 'ac_default_parser.dart';

/// Facade dispatcher for offset pagination with a plain `List<T>`
/// response.
///
/// Uses [ACDefaultParser] — items are taken directly from
/// the result, `hasMore` is computed as
/// `result.length >= params.limit`.
///
/// Example:
///
/// ```dart
/// final dispatcher = ACDefaultDispatcher<UserListParams, User>();
/// await dispatcher.reload(
///   params: const UserListParams(offset: 0, limit: 20),
///   load: (p) => api.fetchUsers(offset: p.offset, limit: p.limit),
/// );
/// ```
///
/// **Extension point**: can be extended to customize loading behavior.
/// Overrides of `notifyListeners`, `dispose`, or internal state mutation
/// must respect the `ChangeNotifier` contract; `super.dispose()` is
/// required.
@Deprecated(
  'Will be removed in 1.0.0. Use ACListDispatcher (offset pagination over '
  'a plain List without the dispatcher+parser composition).',
)
class ACDefaultDispatcher<
        P extends ACOffsetParamsMixin, T>
    extends ACDispatcher<P, List<T>, T> {
  /// Creates a dispatcher with [ACDefaultParser] and an
  /// optional [searchStrategy].
  ACDefaultDispatcher({
    super.searchStrategy,
  }) : super(
          // Deprecated facade сам устаревший: он намеренно опирается на
          // устаревший ACDefaultParser для сохранения паритета поведения
          // 0.2.0 до удаления в 1.0.0.
          // ignore: deprecated_member_use_from_same_package
          parser: ACDefaultParser<P, T>(),
        );
}
