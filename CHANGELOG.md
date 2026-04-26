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
