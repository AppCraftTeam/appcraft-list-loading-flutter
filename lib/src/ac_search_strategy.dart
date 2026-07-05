/// Behavioural component that decides whether a load should be started
/// for a given query, and when.
///
/// Used by the dispatcher inside `reload`. Knowledge of the debounce
/// timer and the last applied query is encapsulated here — the
/// dispatcher does not keep `_debounceTimer` / `_lastAppliedQuery` of
/// its own.
///
/// The default implementation is `ACSearchDebouncer`. This interface is
/// a live seam: custom strategies (e.g. throttle) may implement it.
abstract class ACSearchStrategy {
  /// Decides whether to start a load for [query], and when.
  ///
  /// Returns:
  /// - `null` — rejection by `minLength`: the caller must clear items
  ///   and **not** perform a load;
  /// - `Future<void>` — when it resolves, the load can be started (it
  ///   may resolve immediately or after a debounce).
  ///
  /// Calling [schedule] again cancels the previously pending timer.
  Future<void>? schedule(String? query);

  /// Cancels the pending timer if one is scheduled.
  void cancel();

  /// Releases internal resources (the timer).
  void dispose();
}
