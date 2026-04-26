import 'dart:async';

/// Behavioural component that decides whether a load should be started
/// for a given query, and when.
///
/// Used by the dispatcher inside `reload`. Knowledge of the debounce
/// timer and the last applied query is encapsulated here — the
/// dispatcher does not keep `_debounceTimer` / `_lastAppliedQuery` of
/// its own.
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

/// Default [ACSearchStrategy] implementation: debounce + minLength +
/// tracking of the last applied query.
///
/// Behaviour of [schedule] for a query:
/// - `null` / empty string: `_lastAppliedQuery` is reset, an already
///   completed `Future` is returned (immediate launch);
/// - shorter than [minLength]: `_lastAppliedQuery` is updated, `null`
///   is returned — the caller treats this as a rejection;
/// - equal to `_lastAppliedQuery`: an already completed `Future` is
///   returned;
/// - changed and satisfies [minLength]:
///   - if [debounce] `== Duration.zero` — `_lastAppliedQuery` is
///     updated immediately and a completed `Future` is returned;
///   - otherwise a `Timer(debounce, ...)` is started; on its tick
///     `_lastAppliedQuery` is updated and the completer completes.
final class ACDebouncedSearchStrategy implements ACSearchStrategy {
  /// Creates a strategy with custom [debounce] and [minLength].
  ///
  /// Defaults: `debounce = 300ms`, `minLength = 3`. Both parameters
  /// must be non-negative — checked by runtime asserts.
  ACDebouncedSearchStrategy({
    this.debounce = const Duration(milliseconds: 300),
    this.minLength = 3,
  })  : assert(
          debounce.inMicroseconds >= 0,
          'debounce must be non-negative',
        ),
        assert(minLength >= 0, 'minLength must be non-negative');

  /// Delay before the actual load is started for a changed query.
  final Duration debounce;

  /// Minimum query length at which the search activates.
  final int minLength;

  String? _lastAppliedQuery;
  Timer? _timer;

  @override
  Future<void>? schedule(String? query) {
    _timer?.cancel();
    _timer = null;

    // Empty query — immediate launch, reset last-applied.
    if (query == null || query.isEmpty) {
      _lastAppliedQuery = null;
      return Future<void>.value();
    }

    // Shorter than minLength — rejection (the caller will clear items).
    if (query.length < minLength) {
      _lastAppliedQuery = query;
      return null;
    }

    // Equal to the last applied — immediate launch.
    if (query == _lastAppliedQuery) {
      return Future<void>.value();
    }

    // Changed + satisfies minLength: debounce (or immediate when zero).
    if (debounce == Duration.zero) {
      _lastAppliedQuery = query;
      return Future<void>.value();
    }

    final completer = Completer<void>();
    _timer = Timer(debounce, () {
      _timer = null;
      _lastAppliedQuery = query;
      if (!completer.isCompleted) completer.complete();
    });
    return completer.future;
  }

  @override
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() => cancel();
}
