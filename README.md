# appcraft_list_loading_flutter

[![Pub Version](https://img.shields.io/pub/v/appcraft_list_loading_flutter)](https://pub.dev/packages/appcraft_list_loading_flutter)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A single-purpose Flutter package for paginated list loading. It provides two
self-contained dispatchers — `ACListDispatcher` for a plain `List<T>` response
and `ACPageDispatcher` for a page-model (DTO) response — each encapsulating the
loading lifecycle (reload / loadMore / cancel / dispose). It also ships
parameter mixins for offset- and cursor-based pagination, the `ACPage` page
mixin, and ready-to-use strategies for debounced search and load cancellation.
Suitable for any list with pagination, a search field and pull-to-refresh —
without imposing any specific state-management library (both dispatchers extend
`ChangeNotifier`).

## Features

- Offset pagination via `ACListDispatcher` and
  `ACOffsetParamsMixin`.
- Page-model (DTO) responses with explicit `hasMore` via `ACPageDispatcher` +
  any DTO with the `ACPage` mixin.
- Cursor pagination via a custom `cursor` field on your params class +
  `ACPageDispatcher` + an `ACPage` DTO. Use
  `dispatcher.lastResult?.<your_cursor_field>` to feed the next `loadMore`.
- Debounced search with `minLength` via `ACDebouncedSearchStrategy`.
- Cancellation strategies: the `ACCancelStrategy` contract and a ready
  `ACOperationCancelStrategy` implementation on top of `package:async`.
- Integration with `ChangeNotifier` — subscribe via `ListenableBuilder`,
  `AnimatedBuilder` or `addListener`.
- External list control via `mutate` (realtime/optimistic/seed) with a
  manual `hasMore` setter, on both dispatchers.

> **Deprecated:** `ACDispatcher`, `ACCustomDispatcher`, `ACParser`,
> `ACResultParser` and the `ACResult` model are deprecated and will be removed
> in `1.0.0`. Use the self-contained `ACListDispatcher` / `ACPageDispatcher`
> and the `ACPage` mixin instead. See the [API Reference](#api-reference).

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

### 2. DTO with `ACPage` — `ACPageDispatcher`

If the backend returns a DTO with an explicit `hasMore` flag (and/or a
cursor), the DTO mixes in `ACPage<T>` and `ACPageDispatcher` reads `items`
and `hasMore` from it automatically — no separate parser is needed. Any extra
fields (cursor, metadata) are read back through `dispatcher.lastResult`.

> **Migration note:** the older `ACCustomDispatcher` / `ACResultParser` /
> `ACParser` / `ACDispatcher` classes and the `ACResult` model are deprecated
> and will be removed in `1.0.0`. Migration is mechanical: change the DTO
> mixin `ACResult<T>` → `ACPage<T>` (the members are identical) and the
> dispatcher class `ACCustomDispatcher` → `ACPageDispatcher`. Method
> signatures, getters and behaviour are unchanged; `mutate` and the `hasMore`
> setter are added on top. See the [API Reference](#api-reference).

```dart
import 'package:appcraft_list_loading_flutter/appcraft_list_loading_flutter.dart';

final class UserPageDto with ACPage<User> {
  const UserPageDto({
    required this.items,
    required this.hasMore,
    this.nextCursor,
  });

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
    ACPageDispatcher<UserCursorParams, UserPageDto, User>();

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

`ACPageDispatcher` also supports external list control — `mutate` for
realtime / optimistic / seed writes (a single batched notification) and a
manual `hasMore` setter — with the same rules as `ACListDispatcher`. See
[Manual list control](#manual-list-control--mutate--hasmore).

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

The recommended extension points are the self-contained dispatchers
`ACListDispatcher` and `ACPageDispatcher`: both are open for `extends` and
`implements`, so you can customize loading, search or cancellation behaviour
without copying the source. The strategy classes are open too.

Open classes:

- `ACListDispatcher`
- `ACPageDispatcher`
- `ACDebouncedSearchStrategy`
- `ACOperationCancelStrategy`

The former parser-based extension points — the abstract `ACDispatcher` /
`ACParser` base classes and the `ACResultParser` implementation — are
**deprecated** (removed in `1.0.0`); custom parsing logic now lives inside a
subclass of the relevant dispatcher instead. The `ACSearchStrategy`,
`ACCancelStrategy` contracts and the mixins remain open.

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

### Recommended

- `ACListDispatcher<P, T>` — self-contained dispatcher for offset pagination
  with a plain `List<T>` response, with `reload`, `loadMore`, `cancel` and
  `dispose` methods plus `items`, `isLoading`, `hasMore` and `lastResult`
  getters. Also exposes `mutate(update)` for external list mutation
  (realtime/optimistic/seed) with a single batched notification, and a
  `hasMore` setter for manual pagination control.
- `ACPageDispatcher<P, R, T>` — self-contained dispatcher for a page-model
  (DTO) response `R extends ACPage<T>`. Same lifecycle, getters, `mutate`
  and `hasMore` setter as `ACListDispatcher`; `items` and `hasMore` are read
  directly from the returned page model. `lastResult` exposes the raw `R`
  from the most recent successful load (useful for cursor pagination or DTO
  metadata).
- `ACPage<T>` — page-model contract mixin (`items`, `hasMore`).
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

### Deprecated (removed in `1.0.0`)

- `ACDispatcher<P, R, T>` — parser-composing core dispatcher. Replaced by the
  self-contained `ACListDispatcher` / `ACPageDispatcher`.
- `ACCustomDispatcher<P, R, T>` — facade for DTOs. Replaced by
  `ACPageDispatcher`.
- `ACResult<T>` — DTO contract mixin. Replaced by `ACPage<T>` (identical
  members).
- `ACParser<P, R, T>` — parser strategy interface. Parsing now lives inside a
  dispatcher; no direct replacement.
- `ACResultParser<P, R, T>` — parser for `ACResult` DTOs. Folded into
  `ACPageDispatcher`.
- `ACDefaultDispatcher<P, T>` / `ACDefaultParser<P, T>` — replaced by
  `ACListDispatcher` (identical public contract).

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
