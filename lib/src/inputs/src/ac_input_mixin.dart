/// Миксин для ввода данных в форму.
/// Добавляет свойства для проверки валидности поля.
mixin ACInputMixin {

  /// Проверка валидности поля.
  /// Должна быть реализована в классе, который использует миксин.
  bool get isValid;

  /// Обратная проверка: true, если поле невалидное
  bool get isNotValid => !isValid;
}

/// Расширение для списка объектов с миксином [ACInputMixin]
extension ACInputMixinListExt on List<ACInputMixin> {

  /// Проверка, что все поля в списке валидны
  bool get isValid => every((e) => e.isValid);

  /// Обратная проверка: true, если хотя бы одно поле невалидное
  bool get isNotValid => !isValid;

}