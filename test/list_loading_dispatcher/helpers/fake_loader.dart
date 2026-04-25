import 'dart:async';

/// A controllable fake of a `Future<R> Function(P params)` loader used by
/// `ACListLoadingDispatcher` tests.
///
/// Outcomes are configured via [enqueueValue] and [enqueueError] and consumed
/// in FIFO order — the i-th call resolves with the i-th enqueued outcome.
/// Optional per-call delays are configured via [enqueueDelay] and apply to
/// the matching (next enqueued) outcome only.
///
/// Recorded [calls] and [callCount] let tests assert how the dispatcher
/// invoked the loader.
final class FakeLoader<R> {
  /// Creates an empty fake loader with no enqueued outcomes.
  FakeLoader();

  final List<_Outcome<R>> _outcomes = <_Outcome<R>>[];
  final List<Duration?> _delays = <Duration?>[];
  final List<dynamic> _calls = <dynamic>[];

  /// Enqueues [value] as the next outcome. The matching call will complete
  /// with this value.
  void enqueueValue(R value) {
    _outcomes.add(_Outcome<R>.value(value));
  }

  /// Enqueues [error] as the next outcome. The matching call will complete
  /// with this error.
  void enqueueError(Object error) {
    _outcomes.add(_Outcome<R>.error(error));
  }

  /// Attaches [delay] to the next enqueued outcome's resolution time.
  ///
  /// The delay is aligned positionally: the n-th `enqueueDelay` applies to
  /// the n-th outcome that is resolved. Subsequent outcomes without a
  /// matching delay resolve without any artificial delay.
  void enqueueDelay(Duration delay) {
    _delays.add(delay);
  }

  /// Params values passed to the loader, in invocation order.
  List<dynamic> get calls => List<dynamic>.unmodifiable(_calls);

  /// Number of times the loader was invoked.
  int get callCount => _calls.length;

  /// Clears all enqueued outcomes, delays and recorded calls.
  void reset() {
    _outcomes.clear();
    _delays.clear();
    _calls.clear();
  }

  /// The callable invoked by the dispatcher.
  ///
  /// Records [params] in [calls], then resolves (after any configured delay)
  /// using the next enqueued outcome. Throws [StateError] if the outcome
  /// queue is empty.
  Future<R> call<P>(P params) async {
    final callIndex = _calls.length;
    _calls.add(params);

    if (_outcomes.isEmpty) {
      throw StateError(
        'FakeLoader has no enqueued outcomes for call #${callIndex + 1}',
      );
    }

    final outcome = _outcomes.removeAt(0);
    final delay = _delays.isNotEmpty ? _delays.removeAt(0) : null;

    if (delay != null) {
      await Future<void>.delayed(delay);
    }

    if (outcome.isError) {
      // ignore: only_throw_errors
      throw outcome.error as Object;
    }
    return outcome.value as R;
  }
}

/// A single queued outcome: either a value or an error.
final class _Outcome<R> {
  _Outcome.value(R this.value)
      : error = null,
        isError = false;

  _Outcome.error(Object this.error)
      : value = null,
        isError = true;

  final R? value;
  final Object? error;
  final bool isError;
}
