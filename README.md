# appcraft_list_loading_flutter

[![Pub Version](https://img.shields.io/pub/v/appcraft_list_loading_flutter)](https://pub.dev/packages/appcraft_list_loading_flutter)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Single-purpose Flutter-пакет для пагинированной загрузки списков. Содержит
диспатчер `ACListLoadingDispatcher`, который инкапсулирует жизненный цикл
загрузок (reload / loadMore / cancel / dispose), переиспользуемые парсеры
для «голого» `List<T>` и DTO-ответов, миксины параметров для offset- и
cursor-пагинации, а также готовые стратегии поиска с debounce и отмены
загрузки. Подходит для любых списков с подгрузкой по страницам, поисковой
строкой и pull-to-refresh — без навязывания какой-либо state-management
библиотеки (наследуется от `ChangeNotifier`).

## Features

- Offset-пагинация через `ACDefaultListLoadingDispatcher` и
  `ACOffsetListLoadingParamsMixin`.
- Cursor-пагинация через `ACCursorListLoadingParamsMixin` и любой DTO с
  миксином `ACListLoadingResult`.
- DTO-ответы с явным `hasMore` через `ACCustomListLoadingDispatcher` +
  `ACResultListLoadingParser`.
- Поиск с debounce и `minLength` через `ACDebouncedSearchStrategy`.
- Стратегии отмены: контракт `ACCancelStrategy` и готовая реализация
  `ACOperationCancelStrategy` поверх `package:async`.
- Интеграция с `ChangeNotifier` — подписка через `ListenableBuilder`,
  `AnimatedBuilder` или `addListener`.
- Переиспользуемые парсеры: `ACListLoadingParser`, `ACDefaultListLoadingParser`,
  `ACResultListLoadingParser`.

## Installation

```bash
flutter pub add appcraft_list_loading_flutter
```

## Usage

### 1. Базовый — `ACDefaultListLoadingDispatcher`

Простейший сценарий: loader возвращает голый `List<T>`, offset-пагинация,
без поиска. `hasMore` вычисляется парсером по `result.length >= params.limit`.

```dart
import 'package:appcraft_list_loading_flutter/appcraft_list_loading_flutter.dart';

final class UserListParams
    with ACListLoadingParamsMixin, ACOffsetListLoadingParamsMixin {
  const UserListParams({this.offset, this.limit, this.query});

  @override
  final int? offset;
  @override
  final int? limit;
  @override
  final String? query;
}

final dispatcher = ACDefaultListLoadingDispatcher<UserListParams, User>();

await dispatcher.reload(
  params: const UserListParams(offset: 0, limit: 20),
  load: (p) => api.fetchUsers(offset: p.offset, limit: p.limit),
);

// Подгрузить следующую страницу:
await dispatcher.loadMore(
  params: UserListParams(offset: dispatcher.items.length, limit: 20),
  load: (p) => api.fetchUsers(offset: p.offset, limit: p.limit),
);
```

### 2. DTO с `ACListLoadingResult` — `ACCustomListLoadingDispatcher`

Если бекенд возвращает DTO с явным флагом `hasMore` (или cursor) — DTO
подмешивает миксин `ACListLoadingResult<T>`, а диспатчер сам вытащит
`items` и `hasMore`.

```dart
import 'package:appcraft_list_loading_flutter/appcraft_list_loading_flutter.dart';

final class UserPage with ACListLoadingResult<User> {
  const UserPage({required this.items, required this.hasMore, this.nextCursor});

  @override
  final List<User> items;
  @override
  final bool hasMore;
  final String? nextCursor;
}

final class UserCursorParams
    with ACListLoadingParamsMixin, ACCursorListLoadingParamsMixin {
  const UserCursorParams({this.limit, this.cursor, this.query});

  @override
  final int? limit;
  @override
  final String? cursor;
  @override
  final String? query;
}

final dispatcher =
    ACCustomListLoadingDispatcher<UserCursorParams, UserPage, User>();

await dispatcher.reload(
  params: const UserCursorParams(limit: 20),
  load: (p) => api.fetchUsersPage(cursor: p.cursor, limit: p.limit),
);
```

### 3. Поиск с debounce — `ACDebouncedSearchStrategy`

Стратегия поиска применяется только в `reload`: для query короче `minLength`
items очищаются, для изменившегося query загрузка стартует через `debounce`.
В `loadMore` поиск игнорируется.

```dart
import 'package:appcraft_list_loading_flutter/appcraft_list_loading_flutter.dart';

final dispatcher = ACDefaultListLoadingDispatcher<UserListParams, User>(
  searchStrategy: ACDebouncedSearchStrategy(
    debounce: const Duration(milliseconds: 400),
    minLength: 2,
  ),
);

// Каждое изменение текста переотправляет reload — стратегия сама
// схлопнет частые вызовы в один.
void onQueryChanged(String query) {
  dispatcher.reload(
    params: UserListParams(offset: 0, limit: 20, query: query),
    load: (p) => api.searchUsers(query: p.query, offset: p.offset, limit: p.limit),
  );
}
```

### 4. Кастомная cancel strategy — `ACCancelStrategy`

Если нужна интеграция со собственной системой отмены (например, `Dio`
`CancelToken`), реализуйте `ACCancelStrategy` и передайте экземпляр в
`reload` / `loadMore` через параметр `cancelStrategy`.

```dart
import 'package:appcraft_list_loading_flutter/appcraft_list_loading_flutter.dart';
import 'package:dio/dio.dart';

final class DioCancelStrategy implements ACCancelStrategy {
  DioCancelStrategy() : _token = CancelToken();

  final CancelToken _token;
  bool _completed = false;

  CancelToken get token => _token;

  @override
  Future<T?> run<T>(Future<T> future) async {
    try {
      final result = await future;
      _completed = true;
      return result;
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) return null;
      rethrow;
    }
  }

  @override
  Future<void> cancel() async {
    if (!_completed && !_token.isCancelled) _token.cancel();
  }

  @override
  bool get isActive => !_completed && !_token.isCancelled;
}

await dispatcher.reload(
  params: const UserListParams(offset: 0, limit: 20),
  load: (p) => api.fetchUsers(offset: p.offset, limit: p.limit),
  cancelStrategy: DioCancelStrategy(),
);
```

## API Reference

- `ACListLoadingDispatcher<P, R, T>` — основной диспатчер с методами
  `reload`, `loadMore`, `cancel`, `dispose`.
- `ACDefaultListLoadingDispatcher<P, T>` — фасад для offset-пагинации с
  «голым» `List<T>`-ответом.
- `ACCustomListLoadingDispatcher<P, R, T>` — фасад для DTO с миксином
  `ACListLoadingResult`.
- `ACListLoadingParser<P, R, T>` — strategy-интерфейс парсинга
  результата loader'а.
- `ACDefaultListLoadingParser<P, T>` — реализация парсера для `List<T>`.
- `ACResultListLoadingParser<P, R, T>` — реализация парсера для DTO с
  `ACListLoadingResult`.
- `ACListLoadingResult<T>` — миксин-контракт DTO (`items`, `hasMore`).
- `ACListLoadingParamsMixin` — базовый миксин параметров (`limit`, `query`).
- `ACOffsetListLoadingParamsMixin` — миксин offset-пагинации (`offset`).
- `ACCursorListLoadingParamsMixin` — миксин cursor-пагинации (`cursor`).
- `ACSearchStrategy` — контракт стратегии поиска (`schedule`, `cancel`,
  `dispose`).
- `ACDebouncedSearchStrategy` — реализация стратегии поиска с debounce и
  `minLength`.
- `ACCancelStrategy` — контракт стратегии отмены (`run`, `cancel`,
  `isActive`).
- `ACOperationCancelStrategy` — реализация отмены поверх
  `CancelableOperation` из `package:async`.

Подробная документация — в dartdoc на pub.dev.

## Example

Полный рабочий пример использования — в папке [`example/`](./example).
Демонстрирует offset-пагинацию, поиск с debounce, pull-to-refresh и
infinite scroll в одном экране.

Запуск:

```bash
cd example
flutter pub get
flutter run
```

## License

MIT — см. [LICENSE](./LICENSE).
