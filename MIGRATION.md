# Migration guides

## 1.0.0 → 1.1.0 — `loadAround` is deprecated

Nothing breaks in `1.1.0`: existing code compiles and behaves exactly as
before. What changes is that `loadAround` and the `ACAnchoredPage` model are
now `@Deprecated` — the analyzer will point you at the replacement, and both
are scheduled for removal in `2.0.0`.

### Why

`ACAnchoredDispatcher.loadAround` never built a window around an anchor,
despite its name and its documentation. `ACAnchoredPage` carries a single list,
which `loadAround` seeded into the **newer** side while unconditionally
clearing the older one:

```dart
_newer.mutate((l) => l..clear()..addAll(page.items));
_older.mutate((l) => l.clear());   // <- always empty, whatever the loader returned
```

So the older half of a window was not expressible at all. When the anchor
happened to be the last item of the feed — a chat with no unread messages, for
instance — the window collapsed to a single element and the whole history sat
beyond the edge, reachable only by scrolling up, which a short conversation
does not offer.

### What replaces it

Two independent seeds, one per side, each taking a plain `ACPage`:

| 1.0.0 | 1.1.0 |
|---|---|
| `loadAround(params:, load:)` | `reloadOlder(params:, load:)` + `reloadNewer(params:, load:)` |
| `ACAnchoredPage<T>` (`items`, `hasMoreOlder`, `hasMoreNewer`) | `ACPage<T>` (`items`, `hasMore`) on each side |
| `lastAround` | `lastResultOlder` / `lastResultNewer` |
| `isLoadingAround` | `isReloadingAny` |
| `loadingAroundListenable` | `reloadingAnyListenable` |
| `lastErrorAround` | `lastErrorAny` |
| `errorAroundListenable` | `errorAnyListenable` |

### Before / after

```dart
// Before (1.0.0) — one call, one model, older side always empty
final class ChatAround with ACAnchoredPage<Msg> {
  const ChatAround({
    required this.items,
    required this.hasMoreOlder,
    required this.hasMoreNewer,
    this.olderCursor,
    this.newerCursor,
  });

  @override
  final List<Msg> items;
  @override
  final bool hasMoreOlder;
  @override
  final bool hasMoreNewer;
  final String? olderCursor;
  final String? newerCursor;
}

await d.loadAround(
  params: ChatParams(anchorId: anchorId),
  load: (p) => api.fetchAround(p.anchorId),
);
// d.itemsOlder == []  — always
```

```dart
// After (1.1.0) — two seeds, the existing per-side page model, both sides filled
await Future.wait([
  d.reloadOlder(
    params: ChatParams(anchorId: anchorId, direction: Direction.previous),
    load: api.fetchMessages,   // -> ChatPage, items closest-older -> oldest
  ),
  d.reloadNewer(
    params: ChatParams(anchorId: anchorId, direction: Direction.next),
    load: api.fetchMessages,   // -> ChatPage, items anchor -> newest
  ),
]);
// d.itemsOlder == [m9, m8, m7]; d.itemsNewer == [m10, m11];
// d.items == [m7, m8, m9, m10, m11]
```

The `ChatAround` model is no longer needed — the `ChatPage` you already have
for `loadOlder` / `loadNewer` serves both seeds. Each side's `hasMore` comes
from its own page and describes what lies beyond that side's edge.

### Cursors

`lastAround` existed only because `loadAround` seeded the newer side without
loading it, leaving `lastResultNewer` null. The seeds are real loads, so both
`lastResultOlder` and `lastResultNewer` are populated right after the window is
built — the initial cursors now come from the same members as every subsequent
one:

```dart
// Before
cursor: d.lastResultOlder?.cursor ?? (d.lastAround as ChatAround?)?.olderCursor,

// After
cursor: d.lastResultOlder?.cursor,
```

### What you now own

The package no longer pretends to orchestrate the window. How many requests it
costs, whether the two seeds run concurrently or one after the other, and what
to show when only one of them fails — all yours. A failed side keeps its error
in `lastErrorOlder` / `lastErrorNewer` and can be repeated on its own with
`retryOlder` / `retryNewer`, which now repeat seeds as well as edge loads.

Changing the anchor means seeding **both** sides again. Each seed cancels its
own side's in-flight load and discards its late answer, so no leftover from the
previous anchor can land; seeding just one side is a legitimate call, not a
race, and the dispatcher does not track which anchor a side came from.

### Screen state

```dart
// Before
valueListenable: d.loadingAroundListenable,

// After — true while either side is being seeded, false during edge loads
valueListenable: d.reloadingAnyListenable,
```

`lastErrorAny` holds an error while at least one side has one, so a success on
one side cannot hide a failure on the other.

---

# Migration guide: 0.2.0 → 1.0.0

Version `1.0.0` **removes** the parser-based API entirely. Migration is now
**mandatory**: the deprecated classes are gone, so any code that still uses them
**no longer compiles**. In `0.3.0` these classes were merely `@Deprecated`
(they compiled with a warning) — from `1.0.0` they are deleted.

The removed classes are `ACDispatcher`, `ACCustomDispatcher`,
`ACDefaultDispatcher`, the `ACParser` family (`ACParser`, `ACDefaultParser`,
`ACResultParser`), the `ACResult` model and `ACDebouncedSearchStrategy`. Replace
each of them with the self-contained dispatchers using the mapping table below.
Besides being simpler (no parser to wire up), the new dispatchers are richer:
reactive loading, built-in error state, `retry`, `mutate`, forced load-more and
bidirectional pagination.

## Mapping table

| 0.2.0 (removed in 1.0.0) | 1.0.0 |
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

// After (1.0.0)
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

// After (1.0.0)
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

// After (1.0.0) — standard: no parser needed
final dispatcher = ACPageDispatcher<MyParams, UserPage, User>();

// After (1.0.0) — non-standard pagination: subclass the engine
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

// After (1.0.0)
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

**The one behavioural difference:** a fresh 1.0.0 dispatcher reports
`hasMore == false` **before** the first load (the deprecated dispatchers
reported `true`). So `hasMore` alone already gates a bottom loader, and
`loadMore()` before the first `reload` is a no-op. If your code relied on a
fresh dispatcher reporting `hasMore == true` (e.g. calling `loadMore` first),
call `reload` first, or use `loadMore(force: true)` to bypass the guard.

## Already on 0.3.0 (via the deprecated classes)?

If you upgraded to `0.3.0` but kept using the deprecated parser-based classes
(they still compiled there, with a warning), moving to `1.0.0` is the same
mechanical swap: the deprecated classes are now **removed**, so replace every
remaining use with its new counterpart from the mapping table above. There are
no new steps — once no code references the removed classes, you are on `1.0.0`.

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
