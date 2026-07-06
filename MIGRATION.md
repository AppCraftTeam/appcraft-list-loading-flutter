# Migration guide: 0.2.0 → 0.3.0

Version `0.3.0` is **purely additive** and does **not** break existing code.
Every 0.2.0 public name still compiles and behaves as before — the release only
adds the new self-contained dispatchers alongside the old ones.

The parser-based classes (`ACDispatcher`, `ACCustomDispatcher`,
`ACDefaultDispatcher`, the `ACParser` family, the `ACResult` model and
`ACDebouncedSearchStrategy`) are now **deprecated**. They keep working and stay
exported until `1.0.0`, so migration is **optional** — but it is **recommended**:
the whole parser architecture is going away, and the new dispatchers are simpler
(no parser to wire up) and richer (reactive loading, built-in error state,
`retry`, `mutate`, forced load-more, bidirectional pagination).

## Mapping table

| 0.2.0 (deprecated) | 0.3.0 |
|---|---|
| `ACDefaultDispatcher<P, T>` | `ACListDispatcher<P, T>` |
| `ACCustomDispatcher<P, R, T>` | `ACPageDispatcher<P, R, T>` |
| `ACResult<T>` (mixin) | `ACPage<T>` (mixin) |
| `ACDispatcher<P, R, T>` (base + parser) | `ACLoadingDispatcher` (shared engine) / self-contained dispatchers |
| `ACParser` / `ACDefaultParser` / `ACResultParser` | — (removed: dispatchers are self-contained, no parser needed) |
| `ACDebouncedSearchStrategy` | `ACSearchDebouncer` |

## Before / after

### 1. Offset pagination (plain `List<T>`)

The loader returns a `Future<List<T>>`. Drop the parser and rename the
dispatcher — the `reload` / `loadMore` signatures are identical.

```dart
// Before (0.2.0)
final dispatcher = ACDefaultDispatcher<MyParams, Item>(); // internal ACDefaultParser

await dispatcher.reload(
  params: const MyParams(offset: 0, limit: 20),
  load: (p) => api.fetchItems(offset: p.offset, limit: p.limit), // Future<List<Item>>
);

// After (0.3.0)
final dispatcher = ACListDispatcher<MyParams, Item>(); // no parser

await dispatcher.reload(
  params: const MyParams(offset: 0, limit: 20),
  load: (p) => api.fetchItems(offset: p.offset, limit: p.limit), // Future<List<Item>>
);
```

### 2. DTO / page model (`ACResult` → `ACPage`)

The loader returns a page DTO. Swap the mixin `ACResult<T>` → `ACPage<T>`
(the `items` / `hasMore` members are identical) and the dispatcher class
`ACCustomDispatcher` → `ACPageDispatcher`.

```dart
// Before (0.2.0)
final class UserPage with ACResult<User> {
  const UserPage({required this.items, required this.hasMore});

  @override
  final List<User> items;
  @override
  final bool hasMore;
}

final dispatcher = ACCustomDispatcher<MyParams, UserPage, User>();

await dispatcher.reload(
  params: const MyParams(limit: 20),
  load: (p) => api.fetchUserPage(limit: p.limit), // Future<UserPage>
);

// After (0.3.0)
final class UserPage with ACPage<User> {
  const UserPage({required this.items, required this.hasMore});

  @override
  final List<User> items;
  @override
  final bool hasMore;
}

final dispatcher = ACPageDispatcher<MyParams, UserPage, User>();

await dispatcher.reload(
  params: const MyParams(limit: 20),
  load: (p) => api.fetchUserPage(limit: p.limit), // Future<UserPage>
);
```

### 3. Base dispatcher + parser (custom scheme)

Any code that used the base `ACDispatcher` with an explicit
`parser: ACResultParser()` / `ACDefaultParser()` no longer needs a parser.

- If your pagination is standard, use `ACPageDispatcher` (page model) or
  `ACListDispatcher` (plain list) directly — the parser is gone.
- If your pagination is **non-standard** (custom `hasMore` rule, exotic
  collection state), subclass the now-public engine `ACLoadingDispatcher` and
  implement the hooks (`onLoadSuccess` / `onLoadRejected` / `hasMore`). The whole
  lifecycle (search, cancellation, staleness guards, `isLoading`, `lastResult`,
  error state, `retry`) is inherited.

```dart
// Before (0.2.0) — base dispatcher + parser
final dispatcher = ACDispatcher<MyParams, UserPage, User>(
  parser: const ACResultParser<MyParams, UserPage, User>(),
);

// After (0.3.0) — standard: no parser needed
final dispatcher = ACPageDispatcher<MyParams, UserPage, User>();

// After (0.3.0) — non-standard pagination: subclass the engine
final class MyDispatcher<P extends ACParamsMixin, T>
    extends ACLoadingDispatcher<P, List<T>> {
  MyDispatcher({super.searchStrategy});

  final List<T> _items = <T>[];
  bool _hasMore = true;

  List<T> get items => List<T>.unmodifiable(_items);

  @override
  bool get hasMore => _hasMore;

  @override
  void onLoadSuccess(List<T> result, P params, {required bool replace}) {
    replace ? (_items..clear()..addAll(result)) : _items.addAll(result);
    _hasMore = result.isNotEmpty; // your own pagination rule
    notifyListeners();
  }

  @override
  void onLoadRejected() {
    final wasNonEmpty = _items.isNotEmpty;
    _items.clear();
    _hasMore = false;
    if (wasNonEmpty) notifyListeners();
  }
}
```

### 4. Debounced search

`ACDebouncedSearchStrategy` → `ACSearchDebouncer`: same `debounce` /
`minLength` parameters, identical behaviour — a straight rename. The
`ACSearchStrategy` contract is unchanged for custom implementations.

```dart
// Before (0.2.0)
final dispatcher = ACDefaultDispatcher<MyParams, Item>(
  searchStrategy: ACDebouncedSearchStrategy(
    debounce: const Duration(milliseconds: 400),
    minLength: 2,
  ),
);

// After (0.3.0)
final dispatcher = ACListDispatcher<MyParams, Item>(
  searchStrategy: ACSearchDebouncer(
    debounce: const Duration(milliseconds: 400),
    minLength: 2,
  ),
);
```

## Compatibility note

The `reload` / `loadMore` signatures did **not** change, so the move is
mechanical:

1. rename the dispatcher class (see the mapping table);
2. swap the DTO mixin `ACResult` → `ACPage`;
3. remove the parser (`ACParser` / `ACDefaultParser` / `ACResultParser`).

**The one behavioural difference:** a fresh 0.3.0 dispatcher reports
`hasMore == false` **before** the first load (the deprecated dispatchers
reported `true`). So `hasMore` alone already gates a bottom loader, and
`loadMore()` before the first `reload` is a no-op. If your code relied on a
fresh dispatcher reporting `hasMore == true` (e.g. calling `loadMore` first),
call `reload` first, or use `loadMore(force: true)` to bypass the guard.

## What you get after migrating

The new dispatchers add capabilities the deprecated ones never had:

- **Reactive loading:** `loadingListenable` plus the granular synchronous flags
  `isReloading` / `isLoadingMore`.
- **Built-in error state:** `lastError`, `errorListenable`, `retry()` and
  `lastOperation` (the exception is still propagated — additive on top of your
  `try/catch`).
- **External list control:** `mutate` (realtime / optimistic / seed writes with
  a single batched notification) and a public `hasMore` setter.
- **Forced load-more:** `loadMore(force: true)` to pull past the end of the list
  without a full `reload`.
- **General debounce:** the standalone `ACDebouncer` for debouncing any action
  (read-tracking, autosave, analytics throttling).
- **Bidirectional pagination:** `ACAnchoredDispatcher` (chat / feed pagination
  around an anchor, growing in both directions) plus the `ACAnchoredPage`
  around-page contract.
