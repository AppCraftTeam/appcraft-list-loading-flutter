# appcraft_list_loading_flutter

<!--
Template for future CHANGELOG.md entries:
## <version>

- Brief summary of changes (imperative mood, present tense).
- List of key changes:
  - What was added.
  - What was changed.
  - What was fixed.
  - What was removed or deprecated.
- Each change is a separate bullet, without unnecessary implementation details.
-->

## 0.3.0

> Migration from 0.2.0 → 0.3.0: see [MIGRATION.md](MIGRATION.md).

- **Added:** new self-contained `ACAnchoredDispatcher<P extends ACParamsMixin, R extends ACPage<T>, T>`
  — a bidirectional, anchor-centred dispatcher for chat/feed pagination, built
  as a composition of **two** `ACPageDispatcher`s (one per side), so each side
  reuses the full loading engine (cancellation, staleness guards, `isLoading`,
  `lastResult`, error channels, `retry`, `mutate`). `loadAround` seeds the
  window around an anchor (cancelling any previous around-load and both sides);
  `loadOlder` / `loadNewer` grow each side independently via `loadMore`. Exposes
  the separate `itemsOlder` / `itemsNewer` (for a `CustomScrollView(center:)`
  without scroll jumps) and a merged read-only `items`
  (`reverse(itemsOlder) ++ itemsNewer`), fully per-side state
  (`isLoadingOlder` / `isLoadingNewer` / `isLoadingAround`,
  `hasMoreOlder` / `hasMoreNewer`, `lastErrorOlder/Newer/Around` with matching
  `error*Listenable` and `loading*Listenable`, `lastResultOlder/Newer`,
  `lastAround`, `retryOlder` / `retryNewer`), realtime `mutateOlder` /
  `mutateNewer`, plus `cancel` and an idempotent `dispose`. Cursors are managed
  manually by the consumer (initial ones from `lastAround`, subsequent ones from
  `lastResult*`).
- **Added:** new around-page contract `ACAnchoredPage<T>` (mixin with `items`,
  `hasMoreOlder`, `hasMoreNewer`) — returned by `ACAnchoredDispatcher.loadAround`,
  it carries **both** directional flags at once (unlike the per-side `ACPage`,
  whose `hasMore` means "more on this side"). The per-side `loadOlder` /
  `loadNewer` keep using the existing `ACPage` model.
- Additive only — a new composition on top of two existing `ACPageDispatcher`s;
  no existing class is changed and no migration is required.
- **Added:** new standalone `ACDebouncer` — an action-neutral debounce utility
  that collapses a burst of calls into a single trailing-edge invocation
  (`run(void Function())`, `isActive`, `cancel()`, `dispose()`), with a
  non-negative `duration` (default `300ms`; `Duration.zero` fires on the next
  tick). It knows nothing about loading or search, so it is reusable for any
  debounced behaviour (read-tracking, autosave, analytics throttling, ...).
  `dispose()` is mandatory — it cancels the pending timer so a deferred action
  never fires after teardown.
- **Added:** new `ACSearchDebouncer implements ACSearchStrategy` — the new
  default search strategy on both dispatchers (`debounce: 300ms`,
  `minLength: 3`), built by composing an `ACDebouncer` for timing. Search
  behaviour (empty / `< minLength` / equal / zero / debounce gating) is
  **unchanged** from the previous default. The `ACSearchStrategy` contract is
  kept for custom strategies.
- **Deprecated:** `ACDebouncedSearchStrategy` — will be removed in 1.0.0; use
  `ACSearchDebouncer` instead (same `debounce` / `minLength` parameters and
  identical behaviour — a straight rename). It keeps working and is still
  exported; it was moved to `lib/src/deprecated/`. Additive change — the search
  behaviour of the dispatchers is unchanged and no migration is required beyond
  the optional rename.
- **Changed:** BEHAVIOR CHANGE — a fresh `ACListDispatcher` / `ACPageDispatcher`
  now reports `hasMore == false` before the first load (was `true`), so
  `hasMore` alone already gates a bottom loader without the extra
  `lastResult != null && hasMore` check. As a result, `loadMore()` before the
  first `reload` is a no-op (the `hasMore == false` guard) — use `reload` for
  the first load, or `loadMore(force: true)` to force it (`force` still bypasses
  the `hasMore == false` guard, now including this initial state). The `hasMore`
  computation after a load is unchanged (offset rule / `page.hasMore`), and the
  `hasMore` setter and `minLength` are unaffected. Migration: if you relied on a
  fresh dispatcher reporting `hasMore == true` (e.g. calling `loadMore` first),
  switch to `reload` or `loadMore(force: true)`. Deprecated dispatchers are not
  affected.
- **Added:** built-in error state on `ACLoadingDispatcher` — `Object? lastError`
  (the last thrown object, read synchronously) and
  `ValueListenable<Object?> errorListenable` (its reactive channel, deduplicated
  by value and released in `dispose`). A failing `load` still **propagates** the
  exception exactly as before — the error state is additive, so existing
  `try/catch` around `reload` / `loadMore` keeps working. The error clears on
  the next successful load, and changing `lastError` does not fire
  `notifyListeners()`.
- **Added:** `Future<void> retry()` on `ACLoadingDispatcher` — repeats the last
  operation (`reload` or `loadMore`) through the public methods with the
  original `params` / `load` and, for `loadMore`, the original `force`. A no-op
  when there is no prior operation or after `dispose`.
- **Added:** read-only `ACDispatcherOperation<Params, T>? lastOperation` on
  `ACLoadingDispatcher` for introspecting the captured operation, plus the new
  public sealed model `ACDispatcherOperation` with the variants
  `ACReloadOperation` and `ACLoadMoreOperation` (the latter carrying `force`);
  both expose the common `params` and `load`. An exhaustive `switch` needs no
  default clause.
- All of the above live in the base `ACLoadingDispatcher`, so `ACListDispatcher`,
  `ACPageDispatcher` and third-party subclasses inherit them. Additive only —
  the exception propagation is unchanged (no breaking changes, no migration).
- **Added:** optional `bool force` parameter (default `false`) on
  `ACLoadingDispatcher.loadMore` — force a load past the end of the list by
  bypassing **only** the `hasMore == false` guard, without a full `reload` and
  without losing the accumulated list. It is one-shot (`hasMore` is recomputed
  after a successful load) and keeps every other guard: `force` has no effect
  during an active load or after `dispose`. Additive only — the default `false`
  preserves the previous behaviour, no breaking changes and no migration. Lives
  in the base `ACLoadingDispatcher`, so `ACListDispatcher`, `ACPageDispatcher`
  and third-party subclasses inherit it.
- **Added:** public `ValueListenable<bool> loadingListenable` on
  `ACLoadingDispatcher` — a reactive channel that mirrors the overall
  `isLoading` flag, notifying on every `false ↔ true` transition (deduplicated
  by value). Drive a spinner reactively via `ValueListenableBuilder` or an
  `addListener` in a Cubit/Bloc, without manual `setState` and without
  subscribing to list changes. Released in `dispose`.
- **Added:** public synchronous flags `bool isReloading` and
  `bool isLoadingMore` on `ACLoadingDispatcher` — tell a `reload` (full-screen
  spinner) apart from a `loadMore` (bottom spinner). Exactly one is `true`
  during an active load; both are `false` otherwise. `isLoading` is now the
  derived `isReloading || isLoadingMore`, so its semantics are unchanged.
- All of the above live in the base `ACLoadingDispatcher`, so `ACListDispatcher`,
  `ACPageDispatcher` and third-party subclasses inherit them. Additive only —
  `isLoading` is unchanged and no existing behaviour changes (no breaking
  changes, no migration; there is no separate listenable for the granular
  flags).
- **Added:** new public abstract `ACLoadingDispatcher<Params extends ACParamsMixin, T>`
  — the shared loading engine that owns the whole lifecycle (search
  scheduling, cancellation of a previous load, staleness guards, the
  `isLoading` flag and the typed `lastResult`) behind
  `reload` / `loadMore` / `cancel` / `dispose`. It is also a public
  extension point: subclass it to implement non-standard pagination by
  providing only the collection state and the `hasMore` / `onLoadSuccess` /
  `onLoadRejected` hooks.
- **Changed:** `ACListDispatcher` and `ACPageDispatcher` are now thin
  subclasses of `ACLoadingDispatcher` — the duplicated loading state machine
  lives in one place. Internal refactor only: their public API and behaviour
  are unchanged, no breaking changes and no migration required.
- **Added:** new self-contained `ACPageDispatcher<P extends ACParamsMixin, R extends ACPage<T>, T>`
  for DTO/cursor pagination where the loader returns a page model. It works
  directly with the model — `items` and `hasMore` are read from it — without
  extending `ACDispatcher` and without a parser. Full behavioural parity with
  the deprecated `ACCustomDispatcher`, plus the `mutate` method and the
  `hasMore` setter (same semantics as on `ACListDispatcher`).
- **Added:** new page-model contract `ACPage<T>` (mixin with `items` and
  `hasMore`) — the renamed `ACResult<T>`. DTOs mix in `ACPage` instead.
- **Deprecated:** the parser architecture and the old model — `ACDispatcher`,
  `ACCustomDispatcher`, `ACParser`, `ACResultParser` and `ACResult` — will be
  removed in 1.0.0. Use the self-contained `ACListDispatcher` (plain `List`) or
  `ACPageDispatcher` (`ACPage` model) instead; migrate DTOs from `ACResult` to
  `ACPage`. All keep working and are still exported; they were moved to
  `lib/src/deprecated/`.
- **Added:** `ACListDispatcher.mutate(void Function(List<T> items) update)` —
  the sanctioned way to mutate the accumulated list from outside (realtime
  append, optimistic update, seed). The callback receives the mutable list;
  a single `notifyListeners()` fires on successful completion (batched — many
  operations, one notification). No-op after `dispose`; a callback exception
  propagates without notifying; `lastResult` is untouched. The `items` getter
  stays unmodifiable — direct `items.add(...)` still throws.
- **Added:** public setter `ACListDispatcher.hasMore` — manually control
  whether `loadMore` may fetch (seed / end-of-list). Does not notify
  listeners (parity with the existing "notify only on items change" rule).
- **Added:** new self-contained `ACListDispatcher<P extends ACOffsetParamsMixin, T>`
  for the most common scenario — offset pagination over a plain `List<T>`.
  It does the job directly, without extending `ACDispatcher` and without a
  parser: item extraction and `hasMore` (`result.length >= limit`, or `true`
  when `limit == null`) are built in. Public API is a drop-in match for
  `ACDefaultDispatcher` (per-call `load`, search via `ACSearchStrategy`,
  per-call `cancelStrategy`, `List<T>? lastResult`, identical
  notify/cancel/error/stale-result/guard semantics).
- **Deprecated:** `ACDefaultDispatcher` and `ACDefaultParser` — will be
  removed in 1.0.0; use `ACListDispatcher` instead. Both keep working and
  are still exported; they were moved to `lib/src/deprecated/`.
- No breaking changes — all 0.2.0 public names remain available.

## 0.2.0

- **Added:** public `R? lastResult` getter on `ACDispatcher` — stores the
  last successfully loaded `R` returned by the loader (the same reference,
  no defensive copy). Updated after every successful `reload`/`loadMore`;
  not reset on `minLength` rejection, loader/parser exception, or
  `cancel()`. Reset to `null` by `dispose()`. Useful for cursor pagination
  and DTO scenarios where the response carries metadata beyond
  `items`/`hasMore` — for example, a server-side `nextCursor` token that
  the consumer feeds into the next `loadMore` call.
- **BREAKING CHANGE:** all 9 public types renamed — the `ListLoading`
  prefix was dropped to keep names short. Search/Cancel strategies kept
  their names (no `ListLoading` prefix to begin with). No deprecated
  `typedef` aliases — migrate via find-replace.

  | Old name                              | New name                |
  |---------------------------------------|-------------------------|
  | `ACListLoadingDispatcher`             | `ACDispatcher`          |
  | `ACDefaultListLoadingDispatcher`      | `ACDefaultDispatcher`   |
  | `ACCustomListLoadingDispatcher`       | `ACCustomDispatcher`    |
  | `ACListLoadingParamsMixin`            | `ACParamsMixin`         |
  | `ACOffsetListLoadingParamsMixin`      | `ACOffsetParamsMixin`   |
  | `ACListLoadingParser`                 | `ACParser`              |
  | `ACDefaultListLoadingParser`          | `ACDefaultParser`       |
  | `ACResultListLoadingParser`           | `ACResultParser`        |
  | `ACListLoadingResult`                 | `ACResult`              |

- **BREAKING CHANGE:** flat `lib/src/` layout. The intermediate
  `lib/src/list_loading_dispatcher/list_loading_dispatcher.dart` barrel
  was removed; the six implementation files now live directly in
  `lib/src/`. The public entry point `lib/appcraft_list_loading_flutter.dart`
  exports them directly. Consumers that import via the public entry are
  unaffected; deep imports through `lib/src/list_loading_dispatcher/...`
  must be updated to `lib/src/...`.
- **Removed:** `ACCursorListLoadingParamsMixin` — empty marker mixin not
  read by the dispatcher. Cursor-style params now declare a plain `cursor`
  field on the params class with `ACParamsMixin`. Carry the next-page
  cursor between calls through `dispatcher.lastResult?.<your_field>`.
- **Migration guide:**
  1. Find-replace the 9 type names per the table above.
  2. Drop `ACCursorListLoadingParamsMixin` from your params classes;
     declare a plain `String? cursor` (or any type) field instead.
  3. (Optional) Use `dispatcher.lastResult` to access the raw last loader
     response — for cursor pagination or DTO metadata.
  4. If you used deep imports (`package:appcraft_list_loading_flutter/src/list_loading_dispatcher/...`),
     either switch to the public entry
     `package:appcraft_list_loading_flutter/appcraft_list_loading_flutter.dart`
     or update paths to the flat `package:appcraft_list_loading_flutter/src/...`.

## 0.1.0

- **BREAKING CHANGE:** removed `final` modifier from public concrete classes,
  allowing both `extends` and `implements` for downstream consumers. Affected
  classes: `ACDefaultListLoadingDispatcher`, `ACCustomListLoadingDispatcher`,
  `ACDefaultListLoadingParser`, `ACResultListLoadingParser`,
  `ACDebouncedSearchStrategy`, `ACOperationCancelStrategy`. For consumers
  that did not rely on `final` guarantees, this is a non-breaking relaxation;
  no migration is required.
- Added "Extending the API" section to README with subclassing example.
- Added inheritance/implementation note to dartdoc of all open classes.

## 0.0.1

- Initial package release.
- Added `ACListLoadingDispatcher<P, R, T>` — a dispatcher for paginated list
  loading with support for offset/cursor pagination, search and cancellation.
- Added facade dispatchers `ACDefaultListLoadingDispatcher<P, T>` and
  `ACCustomListLoadingDispatcher<P, R, T>` with pre-configured parsers.
- Added parsers `ACListLoadingParser`, `ACDefaultListLoadingParser`,
  `ACResultListLoadingParser`.
- Added `ACListLoadingResult<T>` mixin for response DTOs.
- Added parameter mixins `ACListLoadingParamsMixin`,
  `ACOffsetListLoadingParamsMixin`, `ACCursorListLoadingParamsMixin`.
- Added search strategy `ACSearchStrategy` with implementation
  `ACDebouncedSearchStrategy` (debounce + minLength).
- Added cancellation strategy `ACCancelStrategy` (contract +
  implementation based on `CancelableOperation`).
