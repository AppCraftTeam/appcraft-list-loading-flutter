import '../../exceptions/src/ac_exception.dart';

/// Абстрактный класс валидации.
/// [V] — тип значения, которое проверяется.
/// [E] — тип ошибки, которая возвращается при нарушении валидации.
abstract class ACValidation<V, E> {
  const ACValidation();

  /// Метод для проверки значения.
  /// Возвращает объект ошибки [E] при некорректном значении или null, если все ок.
  E? validate(V? value); 
}

/// Расширение для списка валидаторов [List<ACValidation>].
/// Позволяет применить несколько проверок к одному значению.
extension ACValidationListExt<V, E> on List<ACValidation<V, E>> {

  /// Применяет все валидаций по очереди к [value].
  /// Если одна из валидаций возвращает ошибку, она сразу возвращается.
  E? validate(V? value) {
    E? result;

    for (final validation in this) {
      result = validation.validate(value);
      if (result != null) break;
    }

    return result;
  }

}

/// Валидация на обязательное заполнение текстового поля
class ACRequiredValidation<T> extends ACValidation<T, Exception> {
  const ACRequiredValidation();

  @override
  Exception? validate(T? value) {
    if (value == null) return const RequiredFieldException();

    // Дополнительно проверяем для String
    if (value is String && value.isEmpty) return const RequiredFieldException();

    // Дополнительно проверяем для Iterable
    if (value is Iterable && value.isEmpty) return const RequiredFieldException();

    return null;
  }

}

/// Валидация на минимальную длину текста
class ACMinLengthValidation extends ACValidation<String, Exception> {
  const ACMinLengthValidation(this.minLength);

  final int minLength;

  @override
  Exception? validate(String? value) =>
    (value ?? '').length < minLength ?
      MinLengthException(minLength) :
      null;

}

/// Валидация на максимальную длину текста
class ACMaxLengthValidation extends ACValidation<String, Exception> {
  const ACMaxLengthValidation(this.maxLength);

  final int maxLength;

  @override
  Exception? validate(String? value) =>
    (value ?? '').length > maxLength ?
      MaxLengthException(maxLength) :
      null;

}

/// Базовая абстрактная валидация по регулярному выражению
abstract class ACRegExpValidation<E> extends ACValidation<String, E> {
  const ACRegExpValidation();

  RegExp get regExp;

  E get error;
  
  @override
  E? validate(String? value) =>
    !regExp.hasMatch(value ?? '') ? error : null;
}

/// Валидация для email с использованием регулярного выражения
class ACEmailValidation extends ACRegExpValidation<Exception> {
  const ACEmailValidation();

  /// Регулярное выражение для проверки email
  static final emailValidRegExp = RegExp(r'^(([^<>()[\]\\.,;:\s@\"]+(\.[^<>()[\]\\.,;:\s@\"]+)*)|(\".+\"))@((\[[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\])|(([a-zA-Z\-0-9]+\.)+[a-zA-Z]{2,}))$');

  @override
  RegExp get regExp => emailValidRegExp;

  @override
  Exception get error => const WrongEmailException();

}