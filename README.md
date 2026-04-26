# appcraft_list_loading_flutter

[![Pub Version](https://img.shields.io/pub/v/appcraft_list_loading_flutter)](https://pub.dev/packages/appcraft_list_loading_flutter)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A single-purpose Flutter package for paginated list loading. It provides the
`ACListLoadingDispatcher`, which encapsulates the loading lifecycle
(reload / loadMore / cancel / dispose), reusable parsers for plain `List<T>`
and DTO responses, parameter mixins for offset- and cursor-based pagination,
and ready-to-use strategies for debounced search and load cancellation.
Suitable for any list with pagination, a search field and pull-to-refresh —
without imposing any specific state-management library (it extends
`ChangeNotifier`).

## Features

- Offset pagination via `ACDefaultListLoadingDispatcher` and
  `ACOffsetListLoadingParamsMixin`.
- Cursor pagination via `ACCursorListLoadingParamsMixin` and any DTO with
  the `ACListLoadingResult` mixin.
- DTO responses with explicit `hasMore` via `ACCustomListLoadingDispatcher` +
  `ACResultListLoadingParser`.
- Debounced search with `minLength` via `ACDebouncedSearchStrategy`.
- Cancellation strategies: the `ACCancelStrategy` contract and a ready
  `ACOperationCancelStrategy` implementation on top of `package:async`.
- Integration with `ChangeNotifier` — subscribe via `ListenableBuilder`,
  `AnimatedBuilder` or `addListener`.
- Reusable parsers: `ACListLoadingParser`, `ACDefaultListLoadingParser`,
  `ACResultListLoadingParser`.

## Installation

```bash
flutter pub add appcraft_list_loading_flutter
```

## Usage

### 1. Basic — `ACDefaultListLoadingDispatcher`

The simplest scenario: the loader returns a plain `List<T>`, offset-based
pagination, no search. `hasMore` is computed by the parser as
`result.length >= params.limit`.

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

// Load the next page:
await dispatcher.loadMore(
  params: UserListParams(offset: dispatcher.items.length, limit: 20),
  load: (p) => api.fetchUsers(offset: p.offset, limit: p.limit),
);
```

### 2. DTO with `ACListLoadingResult` — `ACCustomListLoadingDispatcher`

If the backend returns a DTO with an explicit `hasMore` flag (or cursor),
the DTO mixes in `ACListLoadingResult<T>` and the dispatcher will read
`items` and `hasMore` from it automatically.

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

### 3. Debounced search — `ACDebouncedSearchStrategy`

The search strategy applies only in `reload`: for a query shorter than
`minLength` items are cleared, for a changed query loading starts after
`debounce`. In `loadMore` the search strategy is ignored.

```dart
import 'package:appcraft_list_loading_flutter/appcraft_list_loading_flutter.dart';

final dispatcher = ACDefaultListLoadingDispatcher<UserListParams, User>(
  searchStrategy: ACDebouncedSearchStrategy(
    debounce: const Duration(milliseconds: 400),
    minLength: 2,
  ),
);

// Every text change triggers a reload — the strategy will collapse
// frequent calls into a single one.
void onQueryChanged(String query) {
  dispatcher.reload(
    params: UserListParams(offset: 0, limit: 20, query: query),
    load: (p) => api.searchUsers(query: p.query, offset: p.offset, limit: p.limit),
  );
}
```

### 4. Custom cancel strategy — `ACCancelStrategy`

If you need to integrate with your own cancellation system (for example a
`Dio` `CancelToken`), implement `ACCancelStrategy` and pass an instance to
`reload` / `loadMore` via the `cancelStrategy` parameter.

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

## Extending the API

All public concrete classes in `appcraft_list_loading_flutter` are open for
both `extends` and `implements`. This lets you customize loading, search,
parsing or cancellation behavior without copying the source.

Open classes:

- `ACDefaultListLoadingDispatcher`
- `ACCustomListLoadingDispatcher`
- `ACDefaultListLoadingParser`
- `ACResultListLoadingParser`
- `ACDebouncedSearchStrategy`
- `ACOperationCancelStrategy`

(The abstract classes `ACListLoadingDispatcher`, `ACListLoadingParser`,
`ACSearchStrategy`, `ACCancelStrategy` and the mixins were already open in
prior versions.)

### Example: extending the default dispatcher

```dart
class LoggingDispatcher<P extends ACOffsetListLoadingParamsMixin, T>
    extends ACDefaultListLoadingDispatcher<P, T> {
  LoggingDispatcher({super.searchStrategy});

  @override
  void notifyListeners() {
    print('items: ${items.length}, isLoading: $isLoading');
    super.notifyListeners();
  }
}
```

When extending, respect the parent contract documented in the corresponding
class' API docs. In particular, `ACDefaultListLoadingDispatcher` extends
`ChangeNotifier` — overrides of `dispose()` must call `super.dispose()`.

## API Reference

- `ACListLoadingDispatcher<P, R, T>` — the core dispatcher with `reload`,
  `loadMore`, `cancel` and `dispose` methods.
- `ACDefaultListLoadingDispatcher<P, T>` — facade for offset pagination
  with a plain `List<T>` response.
- `ACCustomListLoadingDispatcher<P, R, T>` — facade for DTOs that mix in
  `ACListLoadingResult`.
- `ACListLoadingParser<P, R, T>` — strategy interface for parsing the
  loader result.
- `ACDefaultListLoadingParser<P, T>` — parser implementation for `List<T>`.
- `ACResultListLoadingParser<P, R, T>` — parser implementation for DTOs
  with `ACListLoadingResult`.
- `ACListLoadingResult<T>` — DTO contract mixin (`items`, `hasMore`).
- `ACListLoadingParamsMixin` — base parameters mixin (`limit`, `query`).
- `ACOffsetListLoadingParamsMixin` — offset pagination mixin (`offset`).
- `ACCursorListLoadingParamsMixin` — cursor pagination mixin (`cursor`).
- `ACSearchStrategy` — search strategy contract (`schedule`, `cancel`,
  `dispose`).
- `ACDebouncedSearchStrategy` — search strategy implementation with
  debounce and `minLength`.
- `ACCancelStrategy` — cancellation strategy contract (`run`, `cancel`,
  `isActive`).
- `ACOperationCancelStrategy` — cancellation implementation on top of
  `CancelableOperation` from `package:async`.

Detailed documentation is available in the dartdoc on pub.dev.

## Example

A complete working example is available in the [`example/`](./example)
folder. It demonstrates offset pagination, debounced search,
pull-to-refresh and infinite scroll on a single screen.

To run it:

```bash
cd example
flutter pub get
flutter run
```

## License

MIT — see [LICENSE](./LICENSE).
