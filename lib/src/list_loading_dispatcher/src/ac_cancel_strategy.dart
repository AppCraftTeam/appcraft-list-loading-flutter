import 'package:async/async.dart';

/// Контракт стратегии отмены активной загрузки.
///
/// Диспатчер создаёт (или получает извне) экземпляр стратегии на каждую
/// активную загрузку и оборачивает `Future` loader'а через [run]. При
/// необходимости прервать ожидание (новый `reload`, `cancel`, `dispose`)
/// диспатчер вызывает [cancel].
///
/// Контракт:
/// - [run] вызывается **не более одного раза** за жизненный цикл стратегии.
///   Повторный вызов — поведение не определено.
/// - [cancel] можно вызывать до или после [run]; повторные вызовы безопасны
///   (no-op) и не бросают исключений.
/// - [isActive] — истина, пока операция запущена и ещё не завершилась
///   (не получен результат и не была выполнена отмена).
///
/// Обратите внимание: стандартные реализации (в частности
/// [ACOperationCancelStrategy]) отменяют **ожидание** результата, но не
/// прерывают саму асинхронную операцию. Например, HTTP-запрос продолжит
/// выполняться в фоне, а его результат будет проигнорирован.
abstract class ACCancelStrategy {
  /// Обернуть [future] и вернуть его результат либо `null`, если стратегия
  /// была отменена через [cancel] до завершения future.
  Future<T?> run<T>(Future<T> future);

  /// Отменить активную операцию. Повторные вызовы — no-op.
  Future<void> cancel();

  /// `true`, если операция запущена через [run] и ещё не завершилась
  /// (не получен результат и не было вызова [cancel]).
  bool get isActive;
}

/// Дефолтная реализация [ACCancelStrategy] поверх `CancelableOperation`
/// из `package:async`.
///
/// Используется диспатчером по умолчанию: если в конструктор
/// `ACListLoadingDispatcher` не передан `defaultCancelStrategy` и в
/// конкретный вызов `reload`/`loadMore` не передан `cancelStrategy` —
/// диспатчер создаёт новую [ACOperationCancelStrategy] на каждую загрузку.
///
/// Важно: эта стратегия не прерывает исходную операцию (например,
/// HTTP-запрос продолжит выполняться на сервере), а лишь отменяет ожидание
/// результата на стороне диспатчера. Результат завершившейся в фоне
/// операции игнорируется.
final class ACOperationCancelStrategy implements ACCancelStrategy {
  /// Создаёт новую стратегию. Экземпляр одноразовый — на одну загрузку.
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
