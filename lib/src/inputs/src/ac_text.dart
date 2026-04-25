import '../../models/src/wrapped_value.dart';
import '../inputs.dart';

/// Класс для текстового поля формы.
/// Наследуется от [ACInput], где:
/// - `String` — тип значения поля
/// - `Exception` — тип ошибки валидации
class ACText extends ACInput<String, Exception> {

  /// Конструктор принимает:
  /// - [value] — текущее значение текста (по умолчанию пустая строка)
  /// - [isPure] — флаг, указывающий, было ли значение изменено пользователем
  /// - [minLength] — минимальная допустимая длина текста
  /// - [maxLength] — максимальная допустимая длина текста
  const ACText({
    super.value = '',
    super.isPure,
    this.minLength,
    this.maxLength
  });

  /// Минимальная длина текста (необязательный параметр)
  final int? minLength;

  /// Максимальная длина текста (необязательный параметр)
  final int? maxLength;

  /// Переопределение метода [validations], который возвращает список валидаторов
  /// для проверки текста на длину и обязательность.
  @override
  List<ACValidation<String, Exception>> validations(String? value) => [
    // Если задана минимальная длина, добавляем проверки:
    // 1. Обязательность заполнения
    // 2. Проверка минимальной длины
    if (minLength != null)...[
      const ACRequiredValidation(),
      ACMinLengthValidation(minLength ?? 0)
    ],

    // Если задана максимальная длина, добавляем проверку
    if (maxLength != null)
      ACMaxLengthValidation(maxLength ?? 0)
  ];

  ACText copyWith({
    String? value,
    bool? isPure,
    WrappedValue<int?>? minLength,
    WrappedValue<int?>? maxLength
  }) => ACText(
    value: value ?? this.value,
    isPure: isPure ?? this.isPure,
    minLength: WrappedValue.resolve(minLength, this.minLength),
    maxLength: WrappedValue.resolve(maxLength, this.maxLength)
  );
}