import 'package:flutter/foundation.dart';

import 'ac_params.dart';

/// The last operation performed by a dispatcher — captured for `retry()` and
/// read-only introspection.
///
/// A sealed hierarchy with two variants:
/// - [ACReloadOperation] — a `reload` call;
/// - [ACLoadMoreOperation] — a `loadMore` call (carrying its `force` flag).
///
/// Because the type is `sealed`, an exhaustive `switch` over its variants
/// requires no default clause, which the dispatcher relies on to re-dispatch
/// the captured operation in `retry()`.
///
/// The stored [load] is the same loader closure that was originally passed to
/// `reload`/`loadMore`; [params] is the request parameters. The operation is
/// immutable and carries no equality (a loader closure cannot be compared), so
/// it does not mix in `EquatableMixin`.
///
/// Generic parameters mirror the dispatcher:
/// - [Params] — the loading parameters type mixing in [ACParamsMixin];
/// - [T] — the loader result type.
@immutable
sealed class ACDispatcherOperation<Params extends ACParamsMixin, T> {
  /// Creates an operation with its [params] and [load] closure.
  const ACDispatcherOperation({required this.params, required this.load});

  /// The request parameters the operation was invoked with.
  final Params params;

  /// The loader closure the operation was invoked with.
  final Future<T> Function(Params params) load;
}

/// A captured `reload` operation.
///
/// Carries only the base [params] and [load]; a reload has no extra state.
final class ACReloadOperation<Params extends ACParamsMixin, T>
    extends ACDispatcherOperation<Params, T> {
  /// Creates a reload operation with its [params] and [load] closure.
  const ACReloadOperation({required super.params, required super.load});
}

/// A captured `loadMore` operation.
///
/// In addition to the base [params] and [load], it preserves the [force] flag
/// so that `retry()` reproduces the original call — including a forced load
/// that bypasses the `hasMore == false` guard.
final class ACLoadMoreOperation<Params extends ACParamsMixin, T>
    extends ACDispatcherOperation<Params, T> {
  /// Creates a loadMore operation with its [params], [load] and [force] flag.
  const ACLoadMoreOperation({
    required super.params,
    required super.load,
    this.force = false,
  });

  /// Whether the original `loadMore` bypassed the `hasMore == false` guard.
  final bool force;
}
