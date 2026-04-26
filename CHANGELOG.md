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
