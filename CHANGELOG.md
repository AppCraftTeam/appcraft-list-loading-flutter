# appcraft_list_loading_flutter

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

## 0.0.1

- Первый релиз пакета.
- Добавлен `ACListLoadingDispatcher<P, R, T>` — диспатчер пагинированной
  загрузки списков с поддержкой offset/cursor пагинации, поиска и отмены.
- Добавлены fassade-диспатчеры `ACDefaultListLoadingDispatcher<P, T>` и
  `ACCustomListLoadingDispatcher<P, R, T>` с преднастроенными парсерами.
- Добавлены парсеры `ACListLoadingParser`, `ACDefaultListLoadingParser`,
  `ACResultListLoadingParser`.
- Добавлен миксин `ACListLoadingResult<T>` для DTO ответов.
- Добавлены миксины параметров `ACListLoadingParamsMixin`,
  `ACOffsetListLoadingParamsMixin`, `ACCursorListLoadingParamsMixin`.
- Добавлена стратегия поиска `ACSearchStrategy` с реализацией
  `ACDebouncedSearchStrategy` (debounce + minLength).
- Добавлена стратегия отмены `ACCancelStrategy` (контракт +
  реализация на `CancelableOperation`).
