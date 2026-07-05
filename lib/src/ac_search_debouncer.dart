import 'dart:async';

import 'ac_debouncer.dart';
import 'ac_search_strategy.dart';

/// Default [ACSearchStrategy]: query-gating (minLength + last-applied
/// tracking) layered on top of a composed [ACDebouncer] for timing.
///
/// Behaviour of [schedule] for a query:
/// - `null` / empty string: `_lastApplied` is reset, an already
///   completed `Future` is returned (immediate launch);
/// - shorter than [minLength]: `_lastApplied` is updated, `null` is
///   returned — the caller treats this as a rejection and clears items;
/// - equal to `_lastApplied`: an already completed `Future` is returned;
/// - changed and satisfies [minLength]:
///   - if the configured debounce `== Duration.zero` — `_lastApplied` is
///     updated immediately and a completed `Future` is returned;
///   - otherwise the load is deferred through the [ACDebouncer]; on its
///     tick `_lastApplied` is updated and the completer completes.
///
/// Timing is delegated to the composed [ACDebouncer], so a repeated
/// [schedule] cancels the previously pending load (trailing-edge).
class ACSearchDebouncer implements ACSearchStrategy {
  /// Creates a strategy with custom [debounce] and [minLength].
  ///
  /// Defaults: `debounce = 300ms`, `minLength = 3`. Both parameters must
  /// be non-negative — checked by runtime asserts.
  ACSearchDebouncer({
    Duration debounce = const Duration(milliseconds: 300),
    this.minLength = 3,
  })  : assert(minLength >= 0, 'minLength must be non-negative'),
        _debouncer = ACDebouncer(debounce);

  /// Minimum query length at which the search activates.
  final int minLength;

  final ACDebouncer _debouncer;

  String? _lastApplied;

  @override
  Future<void>? schedule(String? query) {
    _debouncer.cancel();

    // Empty query — immediate launch, reset last-applied.
    if (query == null || query.isEmpty) {
      _lastApplied = null;
      return Future<void>.value();
    }

    // Shorter than minLength — rejection (the caller will clear items).
    if (query.length < minLength) {
      _lastApplied = query;
      return null;
    }

    // Equal to the last applied — immediate launch.
    if (query == _lastApplied) {
      return Future<void>.value();
    }

    // Changed + satisfies minLength: debounce (or immediate when zero).
    if (_debouncer.duration == Duration.zero) {
      _lastApplied = query;
      return Future<void>.value();
    }

    final completer = Completer<void>();
    _debouncer.run(() {
      _lastApplied = query;
      if (!completer.isCompleted) completer.complete();
    });
    return completer.future;
  }

  @override
  void cancel() => _debouncer.cancel();

  @override
  void dispose() => _debouncer.dispose();
}
