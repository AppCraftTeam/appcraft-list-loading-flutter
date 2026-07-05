import 'dart:async';

/// A standalone, action-neutral debounce utility.
///
/// Collapses a burst of calls into a single trailing-edge invocation:
/// each [run] cancels the previously scheduled action and re-arms the
/// timer, so only the **last** action within a [duration] window is
/// executed.
///
/// The debouncer knows nothing about loading, search or dispatchers — it
/// merely defers an arbitrary `void Function()` by [duration]. This makes
/// it reusable for any debounced behaviour (search, throttled
/// notifications, expensive recomputations, ...).
///
/// Typical usage:
///
/// ```dart
/// final debouncer = ACDebouncer(const Duration(milliseconds: 200));
/// debouncer.run(() => print('fires once, 200ms after the last run'));
/// // ...
/// debouncer.dispose();
/// ```
class ACDebouncer {
  /// Creates a debouncer with the given [duration].
  ///
  /// Defaults to `300ms`. The [duration] must be non-negative — checked
  /// by a runtime assert. A [duration] of `Duration.zero` schedules the
  /// action on the next event-loop tick.
  ACDebouncer([this.duration = const Duration(milliseconds: 300)])
      : assert(
          duration >= Duration.zero,
          'duration must be non-negative',
        );

  /// Delay applied before the scheduled action is executed.
  final Duration duration;

  Timer? _timer;

  /// Schedules [action] to run after [duration].
  ///
  /// If an action is already pending it is cancelled and replaced by
  /// [action] (trailing-edge — the last call within the window wins).
  void run(void Function() action) {
    _timer?.cancel();
    _timer = Timer(duration, () {
      _timer = null;
      action();
    });
  }

  /// Whether an action is currently scheduled and not yet fired.
  bool get isActive => _timer?.isActive ?? false;

  /// Cancels the pending action without executing it.
  ///
  /// After this call [isActive] is `false`.
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  /// Releases internal resources (the timer).
  ///
  /// Equivalent to [cancel]. After disposal the owner must not call
  /// [run] again.
  void dispose() => cancel();
}
