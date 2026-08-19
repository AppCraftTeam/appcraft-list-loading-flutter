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
- Debounced search with `minLength` via the default `ACSearchDebouncer`
  (composed on top of `ACDebouncer`), or your own `ACSearchStrategy`.
- A standalone, action-neutral `ACDebouncer` for debouncing any action
  (read-tracking, autosave, analytics throttling, ...) — no manual `Timer`.
- Cancellation strategies: the `ACCancelStrategy` contract and a ready
  `ACOperationCancelStrategy` implementation on top of `package:async`.
- Integration with `ChangeNotifier` — subscribe via `ListenableBuilder`,
  `AnimatedBuilder` or `addListener`.
- External list control via `mutate` (realtime/optimistic/seed) with a
  manual `hasMore` setter, on both dispatchers.
- Bidirectional, anchor-based pagination for chat/feed via
  `ACAnchoredDispatcher` (a composition of two `ACPageDispatcher`s):
  `reloadOlder` / `reloadNewer` / `loadOlder` / `loadNewer`, separate
  `itemsOlder` / `itemsNewer`
  for a jump-free `CustomScrollView(center:)` plus a merged `items`, fully
  per-side state and realtime `mutateOlder` / `mutateNewer`.

> **Removed in `1.0.0`:** the parser-based `ACDispatcher`, `ACCustomDispatcher`,
> `ACParser`, `ACResultParser` and the `ACResult` model have been removed. Use
> the self-contained `ACListDispatcher` / `ACPageDispatcher` and the `ACPage`
> mixin instead. See the [API Reference](#api-reference). Upgrading from 0.2.0
> or 0.3.0? Follow the step-by-step [migration guide](MIGRATION.md).

## Installation

```bash
flutter pub add appcraft_list_loading_flutter
```

## Usage

### 1. Basic — `ACListDispatcher`

The simplest scenario: the loader returns a plain `List<T>`, offset-based
pagination, no search. `hasMore` is computed as
`result.length >= params.limit`. `ACListDispatcher` is the recommended
dispatcher for this case.

> **Migration note:** the older `ACDefaultDispatcher` / `ACDefaultParser`
> classes were removed in `1.0.0`. Their public contract was identical to
> `ACListDispatcher` — migration is just renaming the class. See the
> [migration guide](MIGRATION.md).

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

#### Before the first load — `hasMore == false`

A fresh dispatcher reports `hasMore == false` until the first load happens, so
`hasMore` alone already means "there is a loaded page and it may have more":

```dart
final dispatcher = ACListDispatcher<UserListParams, User>();
print(dispatcher.hasMore); // false (before any reload)

// No extra gate is needed — this used to require `lastResult != null && hasMore`:
if (dispatcher.hasMore) const BottomLoader(); // won't show before the first load
```

Consequently `loadMore()` before the first `reload` is a no-op (the
`hasMore == false` guard). Use `reload` to perform the first load, or
`loadMore(force: true)` to bypass the guard explicitly:

```dart
await dispatcher.loadMore(params: p, load: api.fetch);              // no-op (hasMore == false)
await dispatcher.loadMore(params: p, load: api.fetch, force: true); // loads (bypasses the guard)
```

After the first `reload` the value is computed as before (offset rule /
`page.hasMore`) — the post-load computation is unchanged.

#### Forcing a load past the end — `loadMore(force: true)`

Reached the end (`hasMore == false`) but new items may have appeared upstream
(for example after posting a message) and you want to pull them in without a
full `reload` and without losing the accumulated list? Pass `force: true`:

```dart
if (dispatcher.hasMore) {
  await dispatcher.loadMore(params: nextParams, load: api.fetch);              // as usual
} else {
  await dispatcher.loadMore(params: nextParams, load: api.fetch, force: true); // pull anyway
}
```

- `force: true` bypasses **only** the `hasMore == false` check; it is one-shot —
  after a successful load `hasMore` is recomputed as usual.
- The other guards are kept: during an active load and after `dispose` it is a
  no-op, and `isLoadingMore` is `true` while it runs (like a normal `loadMore`).
- Without `force` (or `force: false`) the behaviour is unchanged. It lives in
  the base `ACLoadingDispatcher`, so both dispatchers and subclasses inherit it.

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
> `ACParser` / `ACDispatcher` classes and the `ACResult` model were removed in
> `1.0.0`. Migration is mechanical: change the DTO mixin `ACResult<T>` →
> `ACPage<T>` (the members are identical) and the dispatcher class
> `ACCustomDispatcher` → `ACPageDispatcher`. Method signatures, getters and
> behaviour are unchanged; `mutate` and the `hasMore` setter are added on top.
> See the [migration guide](MIGRATION.md).

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

### 3. Bidirectional chat/feed pagination — `ACAnchoredDispatcher`

For a chat or a feed that opens **around** an anchor (first unread message, a
deep-linked item) and then grows in **both** directions — back in time (older)
and forward in time (newer) — use `ACAnchoredDispatcher`. It is built as a
composition of two `ACPageDispatcher`s (one per side), so each side reuses the
full loading engine (cancellation, staleness guards, `isLoading`, `lastResult`,
error channels, `retry`, `mutate`); this class only orchestrates the anchor
load and exposes a merged list view. It extends `ChangeNotifier`.

Every load — seeding a side or growing it from its edge — uses the same
per-side `ACPage` DTO, whose `hasMore` means "is there more **beyond this
side's edge**".

```dart
import 'package:appcraft_list_loading_flutter/appcraft_list_loading_flutter.dart';

// side-page — used by reloadOlder/reloadNewer and loadOlder/loadNewer alike
final class ChatPage with ACPage<Msg> {
  const ChatPage({required this.items, required this.hasMore, this.cursor});

  @override
  final List<Msg> items;
  @override
  final bool hasMore;
  final String? cursor;
}
```

#### Seed the window — `reloadOlder` + `reloadNewer`

A window around an anchor is composed by **you** out of two independent seeds.
Each one replaces its side's items, takes `hasMore` from its own page, cancels
that side's in-flight load and discards its late answer as stale. How many
requests the window costs, whether the seeds run sequentially or concurrently,
and what happens when only one of them fails — all yours to decide.

```dart
final d = ACAnchoredDispatcher<ChatParams, ChatPage, Msg>();

await Future.wait([
  // older half — closest-older -> oldest, the order loadOlder also appends in
  d.reloadOlder(
    params: ChatParams(anchorId: firstUnreadId, direction: Direction.previous),
    load: api.fetchMessages,
  ),
  // newer half — anchor -> newest; the anchor belongs to this side
  d.reloadNewer(
    params: ChatParams(anchorId: firstUnreadId, direction: Direction.next),
    load: api.fetchMessages,
  ),
]);
// d.itemsOlder == [m9, m8, m7]; d.itemsNewer == [m10, m11];
// d.items == [m7, m8, m9, m10, m11]
```

Nothing is reversed inside the package: if your server returns history
chronologically, reverse it before handing it to `reloadOlder`.

Seeding one side leaves the other untouched — which also means that after
changing the anchor you should seed **both** sides. The dispatcher does not
track which anchor a side was seeded from.

#### Grow up/down — `loadOlder` / `loadNewer`

Each side delegates to its dispatcher's `loadMore` (the `!hasMore` /
`isLoading` guards and one-shot `force` apply). Cursors are managed manually
and read uniformly from `lastResultOlder` / `lastResultNewer` — the seeds
commit them just like the edge loads do, so there is no separate source for
the first page.

```dart
if (d.hasMoreOlder) {
  await d.loadOlder(
    params: ChatParams(cursor: d.lastResultOlder?.cursor),
    load: api.fetchMessages, // hasMore = "more beyond the older edge"
  );
}
if (d.hasMoreNewer) {
  await d.loadNewer(
    params: ChatParams(cursor: d.lastResultNewer?.cursor),
    load: api.fetchMessages, // hasMore = "more beyond the newer edge"
  );
}
```

#### Initial-load state — `isReloadingAny` / `lastErrorAny`

`isReloadingAny` is `true` while **either** side is being seeded and stays
`false` during edge loads, so it drives the initial spinner without flickering
on scroll. `lastErrorAny` holds an error while at least one side has one — a
success on one side cannot hide a failure on the other. Both have reactive
channels (`reloadingAnyListenable`, `errorAnyListenable`); for a targeted
reaction use the per-side `lastErrorOlder` / `lastErrorNewer` with
`retryOlder` / `retryNewer`, which repeat the seed as well as the edge load.

> **Deprecated since 1.1.0:** `loadAround` and the `ACAnchoredPage` model.
> Despite its name `loadAround` could never build a window — it always cleared
> the older side — so a window around an anchor was not expressible. Use the
> two seeds above; removal is planned for 2.0.0. See
> [MIGRATION.md](MIGRATION.md).

#### Two lists for `CustomScrollView(center:)` — no scroll jumps

`itemsOlder` (closest-older → oldest) and `itemsNewer` (anchor → newest) are
exposed **separately** so they feed two slivers around a `center` key — growing
the older side does not shift the visible position. A merged, read-only
`items == reverse(itemsOlder) ++ itemsNewer` is also available for consumers
that prefer a single list.

```dart
CustomScrollView(
  center: centerKey,
  anchor: 0.5,
  slivers: [
    if (d.isLoadingOlder) const SliverToBoxAdapter(child: TopSpinner()),
    SliverList.builder(                          // TOP: older, grows up, no jumps
      itemCount: d.itemsOlder.length,
      itemBuilder: (_, i) => MsgTile(d.itemsOlder[i]),
    ),
    SliverList.builder(                          // BOTTOM: anchor + newer
      key: centerKey,
      itemCount: d.itemsNewer.length,
      itemBuilder: (_, i) => MsgTile(d.itemsNewer[i]),
    ),
    if (d.isLoadingNewer) const SliverToBoxAdapter(child: BottomSpinner()),
  ],
);
```

#### Realtime — `mutateNewer` / `mutateOlder`

`mutateOlder` / `mutateNewer` delegate to the respective side's `mutate` — the
only sanctioned write path (the list getters stay unmodifiable). A single
batched `notifyListeners()` fires per call; a no-op after `dispose`.

```dart
socket.onMessage((m) => d.mutateNewer((items) => items.add(m))); // incoming — down
d.mutateNewer((items) => items                                   // optimistic — one notify
  ..removeWhere((x) => x.localId == pending.localId)
  ..add(sent));
```

#### Per-side indicators / errors / retry

Loading, error and retry state is fully **per side** and independent — a load
or a failure on one side never touches the other:
`isLoadingOlder` / `isLoadingNewer`,
`loadingOlderListenable` / `loadingNewerListenable`,
`lastErrorOlder` / `lastErrorNewer` (with matching
`errorOlderListenable` / `errorNewerListenable`),
`retryOlder()` / `retryNewer()`, and `lastResultOlder` / `lastResultNewer`.

Across both sides there are the derived `isReloadingAny` / `lastErrorAny` and
their channels — see [Initial-load state](#initial-load-state--isreloadingany--lasterrorany).

```dart
ValueListenableBuilder<bool>(
  valueListenable: d.loadingOlderListenable,      // spinner on top
  builder: (_, loading, __) => loading ? const TopSpinner() : const SizedBox(),
);
if (d.lastErrorNewer != null) RetryButton(onTap: d.retryNewer); // error at the bottom
```

`cancel()` cancels the around-load and both sides; `dispose()` releases both
sides and is idempotent (any method after `dispose` is a no-op). The per-side
`searchStrategy` is not applied — the dispatcher only uses `loadMore`.

### 4. Debounced search — `ACSearchDebouncer`

`ACSearchDebouncer` is the **default** search strategy on both dispatchers
(a fresh dispatcher already debounces search with `debounce: 300ms`,
`minLength: 3`), so you only pass one to tweak the timing or gating. It is
built on top of the general-purpose `ACDebouncer` (see below) but its search
behaviour is unchanged from before.

The search strategy applies only in `reload`: for a query shorter than
`minLength` items are cleared, for a changed query loading starts after
`debounce`. In `loadMore` the search strategy is ignored.

```dart
import 'package:appcraft_list_loading_flutter/appcraft_list_loading_flutter.dart';

final dispatcher = ACListDispatcher<UserListParams, User>(
  searchStrategy: ACSearchDebouncer(
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

> **Migration note:** `ACDebouncedSearchStrategy` was removed in `1.0.0`.
> Replace it with `ACSearchDebouncer` — same `debounce` / `minLength`
> parameters and identical behaviour, it is a straight rename. The
> `ACSearchStrategy` contract stays for custom strategies. See the
> [migration guide](MIGRATION.md).

For a fully custom search behaviour, implement `ACSearchStrategy` yourself and
pass it as `searchStrategy` — for example an instant, no-debounce strategy:

```dart
final class InstantSearch implements ACSearchStrategy {
  @override
  Future<void>? schedule(String? query) => Future<void>.value();
  @override
  void cancel() {}
  @override
  void dispose() {}
}

final dispatcher =
    ACListDispatcher<UserListParams, User>(searchStrategy: InstantSearch());
```

### 5. Debouncing any action — `ACDebouncer`

`ACSearchDebouncer` handles search timing, but the underlying `ACDebouncer` is
exposed as a standalone, action-neutral utility for debouncing **any**
`void Function()` — read-tracking, resize handling, draft autosave, analytics
throttling — without wiring up a manual `Timer`. It is trailing-edge: each
`run` cancels the previously scheduled action and re-arms, so only the **last**
action within the `duration` window fires.

```dart
import 'package:appcraft_list_loading_flutter/appcraft_list_loading_flutter.dart';

final _readDebouncer = ACDebouncer(const Duration(milliseconds: 400));

// A frequent stream — e.g. "a message scrolled into view":
void onMessageVisible(Message m) =>
    _readDebouncer.run(() => api.markRead(m.id));
// Only the last id within 400ms reaches the API.

@override
void dispose() {
  _readDebouncer.dispose(); // required — otherwise a pending Timer may
  super.dispose();          // fire the action after dispose
}
```

- `duration` defaults to `300ms` and must be non-negative; `Duration.zero`
  schedules the action on the next event-loop tick.
- `isActive` reports whether an action is currently pending; `cancel()` drops
  the pending action without running it.
- `dispose()` is **mandatory** — it cancels the pending timer so a deferred
  action never fires after teardown. It is equivalent to `cancel()`.

### 6. Custom cancel strategy — `ACCancelStrategy`

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

### 7. Reactive loading indicator — `loadingListenable`

Both dispatchers extend `ChangeNotifier`, but `notifyListeners()` fires only
when `items` change — a change of `isLoading` alone does not wake listeners.
To drive a spinner reactively (without manual `setState` and without
subscribing to the list) use `loadingListenable` — a `ValueListenable<bool>`
that mirrors the overall `isLoading` flag, notifies on every `false ↔ true`
transition and deduplicates equal values.

```dart
// In a widget — no setState:
ValueListenableBuilder<bool>(
  valueListenable: dispatcher.loadingListenable,
  builder: (_, isLoading, __) => isLoading
      ? const LinearProgressIndicator()
      : const SizedBox.shrink(),
);

// In a Cubit/Bloc — where setState is unavailable:
dispatcher.loadingListenable.addListener(() {
  emit(state.copyWith(isLoading: dispatcher.isLoading));
});
```

`loadingListenable` is independent of list changes — you no longer subscribe
to the list just to move a spinner.

#### Telling `reload` apart from `loadMore` — `isReloading` / `isLoadingMore`

To render distinct indicators — a full-screen spinner during `reload` versus a
"loading more" spinner at the bottom during `loadMore` — read the two granular
flags synchronously:

```dart
Widget build(BuildContext context) {
  return Column(children: [
    if (dispatcher.isReloading) const FullScreenSpinner(),   // reload in flight
    Expanded(child: ListView(/* dispatcher.items */)),
    if (dispatcher.isLoadingMore) const BottomSpinner(),     // loadMore in flight
  ]);
}
```

- `isReloading` — `true` while a `reload` is in flight.
- `isLoadingMore` — `true` while a `loadMore` is in flight.
- During any active load exactly one granular flag is `true`; starting a
  `reload` while a `loadMore` runs switches to `isReloading` without the
  overall `isLoading` flickering to `false`.

Compatibility: `isLoading` is unchanged — it is now the derived
`isReloading || isLoadingMore`, so existing code keeps working. The granular
flags are read synchronously; there is no separate `ValueListenable` for them
(the reactive channel is on the overall `isLoading` only). Everything lives in
the base `ACLoadingDispatcher`, so `ACListDispatcher`, `ACPageDispatcher` and
third-party subclasses get it for free.

### 8. Built-in error state — `lastError` / `errorListenable` / `retry()`

A failing `load` still **throws** — your `try/catch` around `reload` / `loadMore`
keeps working exactly as before. On top of that the engine now records the
error so a widget can render a "spinner / error / list" state without wiring up
its own error plumbing: `lastError` exposes the last thrown object
synchronously and `errorListenable` (a `ValueListenable<Object?>`) is the
reactive channel. The error clears automatically on the next successful load.

Combine `loadingListenable` and `errorListenable` to drive the three states
from one builder:

```dart
// In a widget — reactive, combining loading + error:
AnimatedBuilder(
  animation: Listenable.merge([dispatcher.loadingListenable, dispatcher.errorListenable]),
  builder: (context, _) {
    if (dispatcher.isLoading) return const CircularProgressIndicator();
    final error = dispatcher.lastError;
    if (error != null) {
      return Column(children: [
        Text('Error: $error'),
        ElevatedButton(onPressed: dispatcher.retry, child: const Text('Retry')),
      ]);
    }
    return MyList(items: dispatcher.items);
  },
);

// In a Cubit/Bloc:
dispatcher.errorListenable.addListener(() {
  emit(state.copyWith(error: dispatcher.lastError));
});
```

- `lastError` — synchronous; `errorListenable` — reactive, deduplicated by
  value.
- The exception is still **propagated** — `lastError` / `errorListenable` are
  additive, not a replacement for `try/catch`.
- Changing `lastError` does not fire `notifyListeners()` — the reactive channel
  is `errorListenable` only.

#### Repeating the last operation — `retry()`

`retry()` re-runs the last operation (`reload` or `loadMore`) through the public
methods, with the original `params`, `load` and — for `loadMore` — the original
`force`, so you do not have to remember the arguments at the call site:

```dart
try {
  await dispatcher.loadMore(params: p, load: api.fetch, force: true);
} catch (_) {
  // later, on a button tap:
  await dispatcher.retry();   // repeats loadMore with force: true and the same params/load
}
```

- A fresh `cancelStrategy` is used; if you need a custom one, call
  `reload` / `loadMore` directly.
- With no prior operation, or after `dispose`, `retry()` is a no-op.

#### Introspecting the last operation — `lastOperation`

`lastOperation` gives read-only access to the captured operation as a `sealed`
`ACDispatcherOperation`, so an exhaustive `switch` needs no default clause:

```dart
switch (dispatcher.lastOperation) {
  case null:
    label = 'No operation yet';
  case ACReloadOperation():
    label = 'Retry load';
  case ACLoadMoreOperation(:final force):
    label = force ? 'Retry forced load-more' : 'Load more';
}
```

The variants are `ACReloadOperation` and `ACLoadMoreOperation` (carrying
`force`); both expose the common `params` and `load`.

Everything lives in the base `ACLoadingDispatcher`, so `ACListDispatcher`,
`ACPageDispatcher` and third-party subclasses inherit it.

## Extending the API

The recommended extension points are the self-contained dispatchers
`ACListDispatcher` and `ACPageDispatcher`: both are open for `extends` and
`implements`, so you can customize loading, search or cancellation behaviour
without copying the source. The strategy classes are open too.

Open classes:

- `ACListDispatcher`
- `ACPageDispatcher`
- `ACLoadingDispatcher` (abstract — the shared loading engine, see below)
- `ACSearchDebouncer`
- `ACOperationCancelStrategy`

The former parser-based extension points — the abstract `ACDispatcher` /
`ACParser` base classes and the `ACResultParser` implementation — were
**removed in `1.0.0`**; custom parsing logic now lives inside a subclass of the
relevant dispatcher instead. The `ACSearchStrategy`, `ACCancelStrategy`
contracts and the mixins remain open.

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

### The shared engine — `ACLoadingDispatcher`

Both dispatchers are thin subclasses of one abstract engine,
`ACLoadingDispatcher<Params, T>`. The engine owns the whole loading
lifecycle — search scheduling, cancellation of a previous load, staleness
guards, the `isLoading` flag (with the granular `isReloading` / `isLoadingMore`
and the reactive `loadingListenable`), the built-in error state
(`lastError` / `errorListenable`) with `retry()` / `lastOperation`, and the
typed `lastResult` — behind `reload` / `loadMore` / `cancel` / `dispose`. A
subclass supplies only the collection state and three hooks: `hasMore`,
`onLoadSuccess` and `onLoadRejected`.

> This is an internal refactor: `ACListDispatcher` and `ACPageDispatcher`
> now share this base, but their public API and behaviour are unchanged —
> existing code needs no migration.

`ACLoadingDispatcher` is also a public extension point. If neither offset
(`List<T>`) nor `ACPage`-model pagination fits your backend, subclass the
engine directly and implement your own `hasMore` rule — the entire
lifecycle is inherited:

```dart
final class MyDispatcher<P extends ACParamsMixin, T>
    extends ACLoadingDispatcher<P, List<T>> {
  MyDispatcher({super.searchStrategy});

  final List<T> _items = <T>[];
  bool _hasMore = true;

  List<T> get items => List<T>.unmodifiable(_items);

  @override
  bool get hasMore => _hasMore;
  set hasMore(bool value) => _hasMore = value;

  void mutate(void Function(List<T> items) update) {
    if (isDisposed) return; // isDisposed — @protected from the base
    update(_items);
    notifyListeners();
  }

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

`reload` / `loadMore` / `cancel` / `dispose` / `runLoad` / `isLoading` /
`lastResult` are inherited — never override them. Notifications are the
subclass' responsibility: the engine never calls `notifyListeners()`; emit
it from the hooks only when the collection actually changes.

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
- `ACAnchoredDispatcher<P, R, T>` — bidirectional, anchor-centred dispatcher
  for chat/feed pagination, built as a composition of two `ACPageDispatcher`s.
  `reloadOlder` / `reloadNewer` seed each side of a window around an anchor;
  `loadOlder` / `loadNewer` grow each side independently. Exposes the separate
  `itemsOlder` / `itemsNewer` (for a `CustomScrollView(center:)` without scroll
  jumps) and a merged read-only `items`, fully per-side state
  (`isLoadingOlder/Newer`, `hasMoreOlder/Newer`, `lastError*` /
  `error*Listenable`, `loading*Listenable`, `lastResultOlder/Newer`,
  `retryOlder/Newer`), the derived `isReloadingAny` / `lastErrorAny` with their
  channels, realtime `mutateOlder` / `mutateNewer`, plus `cancel` and an
  idempotent `dispose`.
- `ACAnchoredPage<T>` — **deprecated since 1.1.0**, removal planned for 2.0.0.
  Around-page contract mixin (`items`, `hasMoreOlder`, `hasMoreNewer`) used by
  the deprecated `loadAround`. It carries a single list, so it cannot express a
  window around an anchor — seed each side with `ACPage` instead.
- `ACLoadingDispatcher<Params, T>` — the abstract loading engine shared by
  both dispatchers. Owns the loading lifecycle (`reload`, `loadMore`,
  `cancel`, `dispose`, `isLoading`, `lastResult`); subclasses provide the
  collection state and the `hasMore` / `onLoadSuccess` / `onLoadRejected`
  hooks. Public extension point for non-standard pagination. Also exposes
  `loadingListenable` (a `ValueListenable<bool>` mirroring `isLoading` for
  reactive spinners), `reloadingListenable` (mirrors `isReloading` alone, and
  unlike `loadingListenable` still fires when a reload starts on top of an
  in-flight `loadMore`) and the synchronous granular flags `isReloading` /
  `isLoadingMore`, plus the built-in error state — `lastError` (synchronous),
  `errorListenable` (a `ValueListenable<Object?>`), `retry()` (repeat the last
  operation) and `lastOperation` (introspection) — inherited by both
  dispatchers.
- `ACDispatcherOperation<Params, T>` — sealed model of the last operation
  captured for `retry()` / `lastOperation`, with the variants
  `ACReloadOperation` and `ACLoadMoreOperation` (the latter carrying `force`);
  both expose the common `params` and `load`.
- `ACPage<T>` — page-model contract mixin (`items`, `hasMore`).
- `ACParamsMixin` — base parameters mixin (`limit`, `query`).
- `ACOffsetParamsMixin` — offset pagination mixin (`offset`).
- `ACSearchStrategy` — search strategy contract (`schedule`, `cancel`,
  `dispose`); implement it for a fully custom search behaviour.
- `ACSearchDebouncer` — default search strategy implementation with
  `debounce` and `minLength`, composed on top of `ACDebouncer`.
- `ACDebouncer` — standalone, action-neutral debounce utility (`run`,
  `isActive`, `cancel`, `dispose`) for deferring any `void Function()`.
- `ACCancelStrategy` — cancellation strategy contract (`run`, `cancel`,
  `isActive`).
- `ACOperationCancelStrategy` — cancellation implementation on top of
  `CancelableOperation` from `package:async`.

### Removed in `1.0.0`

The parser-based API deprecated in `0.3.0` was removed in `1.0.0`. The list
below is kept for historical reference and points to the replacement of each
class — see the [migration guide](MIGRATION.md) for details.

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
- `ACDebouncedSearchStrategy` — replaced by `ACSearchDebouncer` (same
  `debounce` / `minLength` parameters and behaviour).

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
