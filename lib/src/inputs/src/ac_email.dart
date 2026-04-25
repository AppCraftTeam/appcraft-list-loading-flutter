import '../../../appcraft_utils_flutter.dart';

/// Класс для работы с email-полем формы.
/// Наследуется от [ACInput], где:
/// - `String` — тип значения поля
/// - `Exception` — тип ошибки валидации
class ACEmail extends ACInput<String, Exception> {

  /// Конструктор принимает:
  /// - [value] — текущее значение email (по умолчанию пустая строка)
  /// - [isPure] — флаг, указывающий, было ли значение изменено пользователем
  /// - [isRequired] — флаг, указывающий, является ли поле обязательным
  const ACEmail({
    super.value = '',
    super.isPure,
    this.isRequired = false
  });

  /// Флаг обязательности поля
  final bool isRequired;

  /// Переопределение метода [validations], который возвращает список валидаторов для email
  @override
  List<ACValidation<String, Exception>> validations(String? value) =>
    [
      // Если поле обязательное — проверка на заполненность
      if (isRequired) const ACRequiredValidation(),

      // Проверка корректности email через регулярное выражение
      const ACEmailValidation()
    ];

  ACEmail copyWith({
    String? value,
    bool? isPure,
    bool? isRequired
  }) => ACEmail(
    value: value ?? this.value,
    isPure: isPure ?? this.isPure,
    isRequired: isRequired ?? this.isRequired
  );

}