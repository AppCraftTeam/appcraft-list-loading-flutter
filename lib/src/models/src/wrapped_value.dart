/// Класс-обертка для значения типа [T].
/// Используется для явного указания, что значение передается как "обертка",
/// а не напрямую, что удобно для методов `copyWith` и работы с immutable-объектами.
class WrappedValue<T> {

  /// Конструктор для создания обертки с конкретным значением
  const WrappedValue.value(this.value);

  /// Хранимое значение
  final T value;

  /// Статический метод для безопасного извлечения значения из [WrappedValue].
  /// Если [wrappedValue] равен null, возвращается [anotherValue].
  /// Иначе возвращается значение из обертки.
  static T resolve<T>(
    WrappedValue<T>? wrappedValue,
    T anotherValue
  ) => wrappedValue == null ?
    anotherValue :
    wrappedValue.value;
}