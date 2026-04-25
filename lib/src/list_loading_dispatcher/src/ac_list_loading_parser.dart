import 'ac_list_loading_params.dart';
import 'ac_list_loading_result.dart';

/// Стратегия извлечения элементов и флага `hasMore` из результата loader'а.
///
/// Parser позволяет диспатчеру работать с произвольным типом ответа [R]
/// без обязательной обёртки в [ACListLoadingResult]. Это полезно, когда
/// источник возвращает «голый» список (`List<T>`) или DTO со своей схемой
/// полей.
///
/// Контракт:
/// - [extractItems] должен возвращать элементы текущей страницы без
///   побочных эффектов. Для `reload` диспатчер заменяет накопленный список
///   результатом, для `loadMore` — добавляет в конец.
/// - [hasMore] синхронно вычисляет наличие следующей страницы по
///   результату и/или переданным параметрам. Исключения из методов
///   parser'а пробрасываются наружу из `reload`/`loadMore`.
abstract class ACListLoadingParser<P extends ACListLoadingParamsMixin, R, T> {
  /// Конструктор — `const`, чтобы подклассы могли объявлять
  /// `const`-инстансы.
  const ACListLoadingParser();

  /// Извлекает элементы текущей страницы из [result].
  List<T> extractItems(P params, R result);

  /// Определяет, есть ли ещё страницы для догрузки.
  bool hasMore(P params, R result);
}

/// Parser для offset-пагинации: loader возвращает голый `List<T>`.
///
/// `hasMore` вычисляется как `result.length >= params.limit`. Если
/// [ACListLoadingParamsMixin.limit] равен `null`, считается, что источник
/// лимита не имеет и страницы могут продолжаться бесконечно
/// (`hasMore == true`).
final class ACDefaultListLoadingParser<
    P extends ACOffsetListLoadingParamsMixin, T>
    implements ACListLoadingParser<P, List<T>, T> {
  /// Создаёт parser. Экземпляр можно объявлять как `const`.
  const ACDefaultListLoadingParser();

  @override
  List<T> extractItems(P params, List<T> result) => result;

  @override
  bool hasMore(P params, List<T> result) {
    final limit = params.limit;
    if (limit == null) return true;
    return result.length >= limit;
  }
}

/// Parser для DTO, подмешавших [ACListLoadingResult].
///
/// Делегирует оба метода напрямую геттерам результата: [extractItems]
/// возвращает `result.items`, [hasMore] — `result.hasMore`.
final class ACResultListLoadingParser<
    P extends ACListLoadingParamsMixin,
    R extends ACListLoadingResult<T>,
    T> implements ACListLoadingParser<P, R, T> {
  /// Создаёт parser. Экземпляр можно объявлять как `const`.
  const ACResultListLoadingParser();

  @override
  List<T> extractItems(P params, R result) => result.items;

  @override
  bool hasMore(P params, R result) => result.hasMore;
}
