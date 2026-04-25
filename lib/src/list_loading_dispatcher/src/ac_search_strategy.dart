import 'dart:async';

/// Поведенческий компонент, определяющий, нужно ли запускать загрузку для
/// переданного query и когда именно.
///
/// Используется диспатчером внутри `reload`. Знание о debounce-таймере и
/// последнем применённом query инкапсулировано здесь — диспатчер не хранит
/// `_debounceTimer` / `_lastAppliedQuery` самостоятельно.
abstract class ACSearchStrategy {
  /// Решает, нужно ли запускать загрузку для [query], и когда.
  ///
  /// Возвращает:
  /// - `null` — отказ по `minLength`: вызывающий должен очистить items и
  ///   **не** выполнять загрузку;
  /// - `Future<void>` — когда резолвится, загрузку можно стартовать (может
  ///   резолвиться мгновенно или после debounce).
  ///
  /// Повторный вызов [schedule] отменяет предыдущий pending-таймер.
  Future<void>? schedule(String? query);

  /// Отменить pending-таймер, если он запланирован.
  void cancel();

  /// Освободить внутренние ресурсы (таймер).
  void dispose();
}

/// Дефолтная реализация [ACSearchStrategy]: debounce + minLength +
/// отслеживание последнего применённого query.
///
/// Поведение [schedule] для query:
/// - `null` / пустая строка: `_lastAppliedQuery` сбрасывается, возвращается
///   уже завершённый `Future` (мгновенный запуск);
/// - короче [minLength]: `_lastAppliedQuery` обновляется, возвращается
///   `null` — вызывающий трактует это как отказ;
/// - совпадает с `_lastAppliedQuery`: возвращается уже завершённый `Future`;
/// - изменился и удовлетворяет [minLength]:
///   - при [debounce] `== Duration.zero` — `_lastAppliedQuery` обновляется
///     сразу, возвращается завершённый `Future`;
///   - иначе стартует `Timer(debounce, ...)`; по срабатыванию
///     `_lastAppliedQuery` обновляется и completer завершается.
final class ACDebouncedSearchStrategy implements ACSearchStrategy {
  /// Создаёт стратегию с кастомными [debounce] и [minLength].
  ///
  /// По умолчанию: `debounce = 300мс`, `minLength = 3`. Оба параметра
  /// должны быть неотрицательными — проверяется рантайм-ассертами.
  ACDebouncedSearchStrategy({
    this.debounce = const Duration(milliseconds: 300),
    this.minLength = 3,
  })  : assert(
          debounce.inMicroseconds >= 0,
          'debounce must be non-negative',
        ),
        assert(minLength >= 0, 'minLength must be non-negative');

  /// Задержка перед фактическим стартом загрузки для изменившегося query.
  final Duration debounce;

  /// Минимальная длина query, при которой поиск активируется.
  final int minLength;

  String? _lastAppliedQuery;
  Timer? _timer;

  @override
  Future<void>? schedule(String? query) {
    _timer?.cancel();
    _timer = null;

    // Пустой query — мгновенный запуск, сбрасываем last-applied.
    if (query == null || query.isEmpty) {
      _lastAppliedQuery = null;
      return Future<void>.value();
    }

    // Короче minLength — отказ (вызывающий очистит items).
    if (query.length < minLength) {
      _lastAppliedQuery = query;
      return null;
    }

    // Совпал с последним применённым — мгновенный запуск.
    if (query == _lastAppliedQuery) {
      return Future<void>.value();
    }

    // Изменился + удовлетворяет minLength: debounce (или сразу при zero).
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
