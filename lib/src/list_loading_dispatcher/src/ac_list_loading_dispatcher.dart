import 'package:flutter/foundation.dart';

import 'ac_cancel_strategy.dart';
import 'ac_list_loading_params.dart';
import 'ac_list_loading_parser.dart';
import 'ac_list_loading_result.dart';
import 'ac_search_strategy.dart';

/// Диспатчер загрузки списков с пагинацией и поиском.
///
/// Инкапсулирует жизненный цикл загрузок: `reload` перезапускает список с
/// нуля, `loadMore` догружает следующую страницу, `cancel` снимает активную
/// загрузку без сброса накопленных элементов, `dispose` освобождает ресурсы.
///
/// Диспатчер наследуется от [ChangeNotifier]. Состояние доступно через
/// геттеры [items], [isLoading], [hasMore]; [notifyListeners] вызывается
/// только при **изменении [items]** — подписчики `ChangeNotifier` перечитают
/// `items` и сами обновят UI. Изменения [isLoading] или [hasMore] без
/// изменения [items] нотификацию не вызывают; если потребителю нужен
/// спиннер — состояние [isLoading] можно прочитать синхронно до/после
/// `reload`/`loadMore` (например, оборачивая вызов в `setState`).
///
/// Generic-параметры:
/// - [P] — тип параметров загрузки, подмешавший [ACListLoadingParamsMixin]
///   (а также, обычно, один из offset/cursor-миксинов);
/// - [R] — тип результата loader'а. Может быть «голым» `List<T>` или любым
///   DTO — извлечение элементов и `hasMore` инкапсулировано в [parser];
/// - [T] — тип элемента списка.
///
/// Для типовых сценариев удобнее использовать готовые fassade-подклассы:
/// [ACDefaultListLoadingDispatcher] (loader возвращает `List<T>`) и
/// [ACCustomListLoadingDispatcher] (loader возвращает DTO, подмешавший
/// [ACListLoadingResult]).
///
/// Поведение поиска настраивается через [searchStrategy] и применяется
/// только в [reload]: debounce для изменившегося query, отказ при
/// недостижении `minLength` (с очисткой items), мгновенный запуск при
/// пустом или совпавшем query. В [loadMore] поиск игнорируется: query
/// из params передаётся в loader как есть, debounce и проверка minLength
/// не применяются.
///
/// Ошибки loader'а **не** перехватываются: исключение, брошенное внутри
/// `load(params)`, пробрасывается наружу из [reload]/[loadMore]. Флаг
/// [isLoading] при этом гарантированно сбрасывается (через `try/finally`).
class ACListLoadingDispatcher<P extends ACListLoadingParamsMixin, R, T>
    extends ChangeNotifier {
  /// Создаёт диспатчер с обязательным [parser] и опциональной
  /// [searchStrategy].
  ///
  /// [parser] используется в каждом завершённом loader-вызове для
  /// извлечения элементов и флага `hasMore` из результата.
  ///
  /// Если [searchStrategy] не передан — используется
  /// [ACDebouncedSearchStrategy] с дефолтами (debounce `300мс`,
  /// `minLength = 3`). Стратегия задаётся один раз и далее не меняется.
  ACListLoadingDispatcher({
    required this.parser,
    ACSearchStrategy? searchStrategy,
  }) : searchStrategy = searchStrategy ?? ACDebouncedSearchStrategy();

  /// Стратегия извлечения элементов и `hasMore` из результата loader'а.
  final ACListLoadingParser<P, R, T> parser;

  /// Стратегия поискового поведения, применяемая в [reload].
  final ACSearchStrategy searchStrategy;

  final List<T> _items = <T>[];
  bool _isLoading = false;
  bool _hasMore = true;
  bool _disposed = false;
  ACCancelStrategy? _activeCancel;

  /// Неизменяемый список накопленных элементов.
  ///
  /// Возвращается через `List.unmodifiable` — попытка мутировать снаружи
  /// вызывает `UnsupportedError`.
  List<T> get items => List<T>.unmodifiable(_items);

  /// Идёт ли сейчас загрузка.
  ///
  /// Читается синхронно; [notifyListeners] при изменении этого флага
  /// **не** вызывается. Если нужен реактивный спиннер — оборачивайте
  /// вызов `reload`/`loadMore` в `setState`/аналог.
  bool get isLoading => _isLoading;

  /// Есть ли ещё элементы для догрузки через [loadMore].
  ///
  /// Читается синхронно; [notifyListeners] при изменении этого флага
  /// **без** изменения [items] не вызывается.
  bool get hasMore => _hasMore;

  /// Перезагрузить список.
  ///
  /// Поведение определяется [searchStrategy]. Стратегия получает
  /// `params.query` и возвращает:
  /// - `null` — отказ по `minLength`: items очищаются, `hasMore = false`,
  ///   loader **не** вызывается. [notifyListeners] вызывается только если
  ///   список был непустым (то есть [items] действительно изменились);
  /// - `Future<void>` — загрузку нужно стартовать по её завершению
  ///   (мгновенно или после debounce). По резолву `Future` диспатчер
  ///   запускает loader, заменяет накопленные элементы результатом и
  ///   вызывает [notifyListeners].
  ///
  /// Активная загрузка отменяется перед стартом новой через ранее
  /// сохранённый [ACCancelStrategy].
  ///
  /// [load] вызывается с переданными [params]. Тип результата [R]
  /// определяется generic-ом диспатчера; извлечение элементов и
  /// `hasMore` выполняется через [parser]. Исключения loader'а/parser'а
  /// **пробрасываются наружу**; флаг [isLoading] при этом сбрасывается
  /// до того, как исключение покинет метод.
  ///
  /// Результат, пришедший после [dispose] или после того, как успели
  /// стартовать более новый [reload], игнорируется (не применяется к
  /// состоянию и не нотифицирует).
  ///
  /// [cancelStrategy] — опциональная стратегия отмены именно для этой
  /// загрузки. Приоритет: аргумент → новый [ACOperationCancelStrategy]
  /// на каждый вызов. В ветке отказа по minLength [cancelStrategy] не
  /// используется: загрузка не стартует.
  Future<void> reload({
    required P params,
    required Future<R> Function(P params) load,
    ACCancelStrategy? cancelStrategy,
  }) async {
    if (_disposed) return;

    // Выставляем флаг загрузки СИНХРОННО, чтобы вызывающий код сразу после
    // `dispatcher.reload(...)` увидел `isLoading == true` без ожидания
    // debounce-а или внутренних await-ов.
    _isLoading = true;

    final schedule = searchStrategy.schedule(params.query);
    if (schedule == null) {
      // Отказ по minLength — очищаем items.
      final previousCancel = _activeCancel;
      _activeCancel = null;
      if (previousCancel != null) {
        await previousCancel.cancel();
      }
      if (_disposed) return;

      final wasNonEmpty = _items.isNotEmpty;
      _items.clear();
      _hasMore = false;
      _isLoading = false;
      if (wasNonEmpty) notifyListeners();
      return;
    }

    await schedule;
    if (_disposed) return;

    await _runLoad(
      params: params,
      load: load,
      replace: true,
      cancelStrategy: cancelStrategy,
    );
  }

  /// Догрузить следующую страницу.
  ///
  /// Игнорируется (без ошибки, без изменения состояния), если:
  /// - уже идёт другая загрузка (`isLoading == true`);
  /// - [hasMore] == `false`;
  /// - диспатчер уже `dispose`-нут.
  ///
  /// Поиск в [loadMore] не применяется: [searchStrategy] не вызывается,
  /// debounce отсутствует, проверка minLength пропускается. Query из
  /// [params] передаётся в [load] как есть.
  ///
  /// Элементы, извлечённые через [parser], **добавляются** в конец
  /// существующего списка; [hasMore] обновляется по результату parser'а.
  /// По успешной догрузке вызывается [notifyListeners].
  ///
  /// Исключения loader'а/parser'а **пробрасываются наружу**; флаг
  /// [isLoading] при этом сбрасывается до того, как исключение покинет
  /// метод. Накопленные элементы не мутируются в случае ошибки.
  ///
  /// [cancelStrategy] — опциональная стратегия отмены именно для этой
  /// загрузки. Приоритет: аргумент → новый [ACOperationCancelStrategy]
  /// на каждый вызов.
  Future<void> loadMore({
    required P params,
    required Future<R> Function(P params) load,
    ACCancelStrategy? cancelStrategy,
  }) async {
    if (_disposed) return;
    if (_isLoading) return;
    if (!_hasMore) return;

    await _runLoad(
      params: params,
      load: load,
      replace: false,
      cancelStrategy: cancelStrategy,
    );
  }

  /// Отменить активную загрузку (включая pending-таймер в [searchStrategy]).
  ///
  /// Не сбрасывает накопленные [items] и флаг [hasMore]. Если никакой
  /// загрузки не идёт — безопасный no-op. После [dispose] также безопасен
  /// (ничего не делает). [notifyListeners] не вызывается, так как [items]
  /// не меняются.
  Future<void> cancel() async {
    if (_disposed) return;

    searchStrategy.cancel();

    final previousCancel = _activeCancel;
    _activeCancel = null;
    await previousCancel?.cancel();
    if (_disposed) return;

    _isLoading = false;
  }

  /// Освободить ресурсы.
  ///
  /// Отменяет активную загрузку и pending-таймер [searchStrategy] (ошибки
  /// отмены игнорируются), освобождает ресурсы стратегии поиска и
  /// помечает диспатчер как освобождённый. Повторный [dispose] —
  /// идемпотентный no-op. Любые публичные методы, вызванные после
  /// [dispose], становятся no-op и не мутируют состояние.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;

    searchStrategy.dispose();

    // Отмена активной загрузки — fire-and-forget: ошибки игнорируются,
    // приоритет освобождения ресурсов.
    final previousCancel = _activeCancel;
    _activeCancel = null;
    if (previousCancel != null) {
      // Не await-им: dispose ChangeNotifier синхронный. Результат cancel
      // уже никому не нужен.
      previousCancel.cancel().ignore();
    }

    super.dispose();
  }

  /// Общая процедура выполнения загрузки для [reload] и [loadMore].
  ///
  /// При `replace == true` накопленные элементы заменяются результатом
  /// loader'а; при `replace == false` — добавляются в конец (loadMore).
  ///
  /// [cancelStrategy] выбирается по приоритету: аргумент → новый
  /// [ACOperationCancelStrategy]. Выбранный экземпляр сохраняется в
  /// `_activeCancel`, чтобы следующий [reload] мог его отменить.
  ///
  /// Извлечение элементов и `hasMore` делегируется в [parser]. Исключения
  /// loader'а/parser'а не перехватываются: `try/finally` гарантирует
  /// сброс [_isLoading] до пробрасывания исключения наружу.
  Future<void> _runLoad({
    required P params,
    required Future<R> Function(P params) load,
    required bool replace,
    ACCancelStrategy? cancelStrategy,
  }) async {
    if (_disposed) return;

    final previousCancel = _activeCancel;
    final capturedCancel = cancelStrategy ?? ACOperationCancelStrategy();
    _activeCancel = capturedCancel;
    _isLoading = true;

    if (previousCancel != null) {
      await previousCancel.cancel();
    }
    if (_disposed || !identical(_activeCancel, capturedCancel)) {
      return;
    }

    try {
      final result = await capturedCancel.run<R>(load(params));
      if (_disposed || !identical(_activeCancel, capturedCancel)) return;
      if (result == null) return; // отменено

      final newItems = parser.extractItems(params, result);
      final newHasMore = parser.hasMore(params, result);

      if (replace) {
        _items
          ..clear()
          ..addAll(newItems);
      } else {
        _items.addAll(newItems);
      }
      _hasMore = newHasMore;
      notifyListeners();
    } finally {
      if (!_disposed && identical(_activeCancel, capturedCancel)) {
        _isLoading = false;
      }
    }
  }
}

/// Fassade-диспатчер для offset-пагинации с «голым» `List<T>`-ответом.
///
/// Использует [ACDefaultListLoadingParser] — элементы берутся напрямую из
/// результата, `hasMore` вычисляется как `result.length >= params.limit`.
///
/// Пример:
///
/// ```dart
/// final dispatcher = ACDefaultListLoadingDispatcher<UserListParams, User>();
/// await dispatcher.reload(
///   params: const UserListParams(offset: 0, limit: 20),
///   load: (p) => api.fetchUsers(offset: p.offset, limit: p.limit),
/// );
/// ```
final class ACDefaultListLoadingDispatcher<
        P extends ACOffsetListLoadingParamsMixin, T>
    extends ACListLoadingDispatcher<P, List<T>, T> {
  /// Создаёт диспатчер с [ACDefaultListLoadingParser] и опциональной
  /// [searchStrategy].
  ACDefaultListLoadingDispatcher({
    super.searchStrategy,
  }) : super(
          parser: ACDefaultListLoadingParser<P, T>(),
        );
}

/// Fassade-диспатчер для DTO, подмешавших [ACListLoadingResult].
///
/// Использует [ACResultListLoadingParser] — элементы и `hasMore` берутся
/// из соответствующих геттеров результата.
///
/// Пример:
///
/// ```dart
/// final dispatcher =
///     ACCustomListLoadingDispatcher<UserCursorParams, UserPage, User>();
/// await dispatcher.reload(
///   params: const UserCursorParams(cursor: null),
///   load: (p) => api.fetchUsers(cursor: p.cursor),
/// );
/// ```
final class ACCustomListLoadingDispatcher<
        P extends ACListLoadingParamsMixin,
        R extends ACListLoadingResult<T>,
        T> extends ACListLoadingDispatcher<P, R, T> {
  /// Создаёт диспатчер с [ACResultListLoadingParser] и опциональной
  /// [searchStrategy].
  ACCustomListLoadingDispatcher({
    super.searchStrategy,
  }) : super(
          parser: ACResultListLoadingParser<P, R, T>(),
        );
}
