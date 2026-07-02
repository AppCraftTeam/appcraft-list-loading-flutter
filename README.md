# appcraft_list_loading_flutter

[![Pub Version](https://img.shields.io/pub/v/appcraft_list_loading_flutter)](https://pub.dev/packages/appcraft_list_loading_flutter)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A single-purpose Flutter package for paginated list loading. It provides the
`ACDispatcher`, which encapsulates the loading lifecycle
(reload / loadMore / cancel / dispose), reusable parsers for plain `List<T>`
and DTO responses, parameter mixins for offset- and cursor-based pagination,
and ready-to-use strategies for debounced search and load cancellation.
Suitable for any list with pagination, a search field and pull-to-refresh —
without imposing any specific state-management library (it extends
`ChangeNotifier`).

## Features

- Offset pagination via `ACListDispatcher` and
  `ACOffsetParamsMixin`.
- Cursor pagination via a custom `cursor` field on your params class +
  `ACCustomDispatcher` + any DTO with the `ACResult` mixin. Use
  `dispatcher.lastResult?.<your_cursor_field>` to feed the next `loadMore`.
- DTO responses with explicit `hasMore` via `ACCustomDispatcher` +
  `ACResultParser`.
- Debounced search with `minLength` via `ACDebouncedSearchStrategy`.
- Cancellation strategies: the `ACCancelStrategy` contract and a ready
  `ACOperationCancelStrategy` implementation on top of `package:async`.
- Integration with `ChangeNotifier` — subscribe via `ListenableBuilder`,
  `AnimatedBuilder` or `addListener`.
- Reusable parsers: `ACParser`, `ACResultParser`.

## Installation

```bash
flutter pub add appcraft_list_loading_flutter
```

## Usage

### 1. Basic — `ACListDispatcher`

The simplest scenario: the loader returns a plain `List<T>`, offset-based
pagination, no search. `hasMore` is computed by the parser as
`result.length >= params.limit`. `ACListDispatcher` is the recommended
dispatcher for this case.

> **Migration note:** the older `ACDefaultDispatcher` / `ACDefaultParser`
> classes are deprecated and will be removed in `1.0.0`. Their public
> contract is identical to `ACListDispatcher` — migration is just renaming
> the class. See the [API Reference](#api-reference).

```dart
import 'package:appcraft_list_loading_flutter/appcraft_list_loading_flutter.dart';

final class UserListParams
    with ACParamsMixin, ACOffsetParamsMixin {
  const UserListParams({this.offset, this.limit, this.query});

  @override
  final int? offset;
  @override
  final int? limit;
  @override
  final String? query;
}

final dispatcher = ACListDispatcher<UserListParams, User>();

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

#### Manual list control — `mutate` & `hasMore`

For live feeds (realtime append, optimistic update, seed) you can change the
accumulated list from outside via `mutate`. The callback receives the mutable
list; a single `notifyListeners()` fires on success (batched — many operations,
one notification). The `items` getter stays unmodifiable, so `mutate` is the
only sanctioned write path.

```dart
// realtime: an incoming item over WebSocket
socket.onMessage((msg) => dispatcher.mutate((items) => items.add(msg)));

// optimistic: show "sending", then replace with the server object
dispatcher.mutate((items) => items.add(pending));
final sent = await api.send(text);
dispatcher.mutate((items) => items          // two ops → one notification
  ..removeWhere((m) => m.localId == pending.localId)
  ..add(sent));

// remove
dispatcher.mutate((items) => items.removeWhere((m) => m.id == deletedId));

// seed from cache and control pagination manually
dispatcher.mutate((items) => items.addAll(cached));
dispatcher.hasMore = true;   // enable loadMore; set false to stop it
```

Notes: `mutate` is a no-op after `dispose`; a callback exception propagates
without notifying; `mutate`/`hasMore =` do not cancel an active load (a
concurrent `reload` will overwrite manual changes — call `cancel()` first to
seed safely). The `hasMore` setter does not notify listeners. Direct
`dispatcher.items.add(...)` throws `UnsupportedError` — use `mutate`.

### 2. DTO with `ACResult` — `ACCustomDispatcher`

If the backend returns a DTO with an explicit `hasMore` flag (or cursor),
the DTO mixes in `ACResult<T>` and the dispatcher will read
`items` and `hasMore` from it automatically.

```dart
import 'package:appcraft_list_loading_flutter/appcraft_list_loading_flutter.dart';

final class UserPage with ACResult<User> {
  const UserPage({required this.items, required this.hasMore, this.nextCursor});

  @override
  final List<User> items;
  @override
  final bool hasMore;
  final String? nextCursor;
}

final class UserCursorParams with ACParamsMixin {
  const UserCursorParams({this.limit, this.cursor, this.query});

  @override
  final int? limit;
  final String? cursor;
  @override
  final String? query;
}

final dispatcher =
    ACCustomDispatcher<UserCursorParams, UserPage, User>();

await dispatcher.reload(
  params: const UserCursorParams(limit: 20),
  load: (p) => api.fetchUsersPage(cursor: p.cursor, limit: p.limit),
);

// Carry the next-page cursor through the dispatcher's lastResult getter:
await dispatcher.loadMore(
  params: UserCursorParams(
    limit: 20,
    cursor: dispatcher.lastResult?.nextCursor,
  ),
  load: (p) => api.fetchUsersPage(cursor: p.cursor, limit: p.limit),
);
```

### 3. Debounced search — `ACDebouncedSearchStrategy`

The search strategy applies only in `reload`: for a query shorter than
`minLength` items are cleared, for a changed query loading starts after
`debounce`. In `loadMore` the search strategy is ignored.

```dart
import 'package:appcraft_list_loading_flutter/appcraft_list_loading_flutter.dart';

final dispatcher = ACListDispatcher<UserListParams, User>(
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

- `ACListDispatcher`
- `ACCustomDispatcher`
- `ACResultParser`
- `ACDebouncedSearchStrategy`
- `ACOperationCancelStrategy`

(The abstract classes `ACDispatcher`, `ACParser`,
`ACSearchStrategy`, `ACCancelStrategy` and the mixins were already open in
prior versions.)

### Example: extending the list dispatcher

```dart
class LoggingDispatcher<P extends ACOffsetParamsMixin, T>
    extends ACListDispatcher<P, T> {
  LoggingDispatcher({super.searchStrategy});

  @override
  void notifyListeners() {
    print('items: ${items.length}, isLoading: $isLoading');
    super.notifyListeners();
  }
}
```

When extending, respect the parent contract documented in the corresponding
class' API docs. In particular, `ACListDispatcher` extends
`ChangeNotifier` — overrides of `dispose()` must call `super.dispose()`.

## API Reference

- `ACDispatcher<P, R, T>` — the core dispatcher with `reload`,
  `loadMore`, `cancel` and `dispose` methods, plus `items`, `isLoading`,
  `hasMore`, and `lastResult` getters. `lastResult` exposes the raw `R`
  returned by the most recent successful load (useful for cursor
  pagination or DTO metadata).
- `ACListDispatcher<P, T>` — recommended facade for offset pagination
  with a plain `List<T>` response. Also exposes `mutate(update)` for
  external list mutation (realtime/optimistic/seed) with a single batched
  notification, and a `hasMore` setter for manual pagination control.
- `ACCustomDispatcher<P, R, T>` — facade for DTOs that mix in
  `ACResult`.
- `ACParser<P, R, T>` — strategy interface for parsing the
  loader result.
- `ACResultParser<P, R, T>` — parser implementation for DTOs
  with `ACResult`.
- `ACDefaultDispatcher<P, T>` / `ACDefaultParser<P, T>` — **deprecated**,
  removed in `1.0.0`. Use `ACListDispatcher` instead; the public contract
  is identical.
- `ACResult<T>` — DTO contract mixin (`items`, `hasMore`).
- `ACParamsMixin` — base parameters mixin (`limit`, `query`).
- `ACOffsetParamsMixin` — offset pagination mixin (`offset`).
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
