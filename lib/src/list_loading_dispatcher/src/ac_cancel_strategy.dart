import 'package:async/async.dart';

/// Contract for the strategy that cancels an active load.
///
/// The dispatcher creates (or receives from outside) a strategy instance
/// for each active load and wraps the loader's `Future` via [run]. When
/// the wait needs to be aborted (a new `reload`, `cancel`, `dispose`)
/// the dispatcher calls [cancel].
///
/// Contract:
/// - [run] is called **at most once** during the strategy's lifecycle.
///   Calling it again has undefined behaviour.
/// - [cancel] may be called before or after [run]; repeated calls are
///   safe (no-op) and do not throw.
/// - [isActive] is `true` while the operation is running and has not yet
///   finished (no result has been received and no cancellation has
///   happened).
///
/// Note: the standard implementations (in particular
/// [ACOperationCancelStrategy]) cancel the **wait** for the result, but
/// do not abort the asynchronous operation itself. For example, an HTTP
/// request will keep running in the background and its result will be
/// ignored.
abstract class ACCancelStrategy {
  /// Wraps [future] and returns its result, or `null` if the strategy
  /// was cancelled via [cancel] before the future completed.
  Future<T?> run<T>(Future<T> future);

  /// Cancels the active operation. Repeated calls are a no-op.
  Future<void> cancel();

  /// `true` if an operation has been started via [run] and has not yet
  /// finished (no result received and no [cancel] call).
  bool get isActive;
}

/// Default [ACCancelStrategy] implementation on top of
/// `CancelableOperation` from `package:async`.
///
/// Used by the dispatcher by default: if `defaultCancelStrategy` is not
/// passed to the `ACListLoadingDispatcher` constructor and a particular
/// `reload`/`loadMore` call does not receive a `cancelStrategy`, the
/// dispatcher creates a new [ACOperationCancelStrategy] for each load.
///
/// Important: this strategy does not abort the underlying operation
/// (for example, an HTTP request will keep running on the server), it
/// only cancels the wait for the result on the dispatcher's side. The
/// result of the operation that finished in the background is ignored.
///
/// **Extension point**: can be extended or implemented. Subclasses must
/// keep `cancel()` idempotent and `isActive` consistent with the
/// run/cancel lifecycle (per `ACCancelStrategy` contract).
class ACOperationCancelStrategy implements ACCancelStrategy {
  /// Creates a new strategy. The instance is single-use — one per load.
  ACOperationCancelStrategy();

  CancelableOperation<Object?>? _operation;

  @override
  Future<T?> run<T>(Future<T> future) async {
    final operation = CancelableOperation<Object?>.fromFuture(future);
    _operation = operation;
    final result = await operation.valueOrCancellation();
    return result as T?;
  }

  @override
  Future<void> cancel() async {
    await _operation?.cancel();
  }

  @override
  bool get isActive {
    final operation = _operation;
    return operation != null
        && !operation.isCompleted
        && !operation.isCanceled;
  }
}
