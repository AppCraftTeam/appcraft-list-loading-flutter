# appcraft_utils_flutter

<!--
Шаблон для будущих версий CHANGELOG.md:
## <version>

- Краткое описание изменений (императивный стиль, настоящее время).
- Список ключевых изменений:
  - Что добавлено.
  - Что изменено.
  - Что исправлено.
  - Что удалено или устарело.
- Каждое изменение — отдельный пункт, без лишних деталей реализации.
-->

## 0.1.0

- Добавлен `ACListLoadingDispatcher<P, R, T>` — доменный компонент для загрузки списков с пагинацией и поиском.
  - Диспатчер расширяет `ChangeNotifier` из `package:flutter/foundation.dart`; подписка через `addListener` / `ListenableBuilder`.
  - Методы `reload`, `loadMore`, `cancel`, `dispose` (синхронный).
  - Публичные геттеры: `items` (unmodifiable), `isLoading`, `hasMore`, `searchStrategy`, `parser`.
  - `notifyListeners()` вызывается только при изменении накопленного списка элементов.
  - Исключения loader'а пробрасываются наружу через возвращённый Future; флаг `isLoading` сбрасывается через `try/finally`.
- Добавлен `ACListLoadingParser<P, R, T>` — strategy-интерфейс с методами `extractItems(params, result)` и `hasMore(params, result)`. Передаётся в диспатчер обязательным параметром конструктора.
  - `ACDefaultListLoadingParser<P, T>` — для offset-пагинации: loader возвращает голый `List<T>`, `hasMore` вычисляется по `params.limit`.
  - `ACResultListLoadingParser<P, R, T>` — для DTO, подмешавших `ACListLoadingResult<T>`; делегирует в поля DTO.
- Добавлены fassade-диспатчеры с преднастроенным парсером:
  - `ACDefaultListLoadingDispatcher<P, T>` — offset + голый `List<T>`.
  - `ACCustomListLoadingDispatcher<P, R, T>` — DTO с `ACListLoadingResult<T>` миксином.
- Миксин `ACListLoadingResult<T>` — контракт DTO (`items`, `hasMore`) для Custom-кейса.
- Добавлена иерархия миксинов параметров:
  - `ACListLoadingParamsMixin` — базовый контракт (`limit`, `query`).
  - `ACOffsetListLoadingParamsMixin on ACListLoadingParamsMixin` — добавляет `offset` для offset-пагинации.
  - `ACCursorListLoadingParamsMixin on ACListLoadingParamsMixin` — добавляет `cursor` для cursor-пагинации.
  - Диспатчер принимает любой `P extends ACListLoadingParamsMixin` — пользователь выбирает подходящую пару под свой API.
- Добавлена поведенческая стратегия поиска:
  - `abstract class ACSearchStrategy` с методами `schedule`, `cancel`, `dispose`.
  - Дефолтная реализация `ACDebouncedSearchStrategy` (debounce 300 мс / minLength 3); хранит таймер и последний применённый query внутри себя.
- Добавлена стратегия отмены:
  - `abstract class ACCancelStrategy` (`run`, `cancel`, `isActive`).
  - Дефолтная реализация `ACOperationCancelStrategy` на `CancelableOperation` из `package:async`.
  - Параметр `cancelStrategy` задаётся только per-call (в методах `reload`/`loadMore`).
- Поддержка offset, cursor и произвольных стратегий пагинации через миксин `ACListLoadingResult` (без parser-колбэка).
- Пакет теперь Flutter-совместим: явная зависимость от `flutter: sdk: flutter`.
- Новая runtime-зависимость: `async: ^2.11.0`.

## 0.0.3

- Добавлен ACEntityMapper.
- Добавлены ACEnumByNameOrNull и ACEnumComparisonOperators.

## 0.0.2

- Добавлены комментарии в код.
- Изменена валидация `ACRequiredValidation`:
  - Поддержка любых типов значений.
  - Проверка на null.
  - Проверка пустой строки (`String`).
  - Проверка пустой коллекции (`Iterable`).

## 0.0.1

- Начальная версия.
