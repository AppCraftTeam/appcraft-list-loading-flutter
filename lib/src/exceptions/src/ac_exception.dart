import '../../../appcraft_utils_flutter.dart';

final _localization = ACLocalizationManager.instance.localization;

/// Абстрактный класс для пользовательских исключений в приложении.
/// Наследуется от стандартного Exception.
abstract class ACException implements Exception {
  const ACException();

  /// Метод возвращает локализованное сообщение об ошибке.
  /// [localeName] — опциональный параметр для указания конкретной локали.
  String localizedMessage([String? localeName]);

  @override
  String toString() => localizedMessage();
}

/// Исключение для функционала, который еще не реализован (Work In Progress)
class WipException extends ACException {
  const WipException();

  @override
  String localizedMessage([String? localeName]) =>
    _localization(localeName).wipException;
}

/// Исключение, когда какой-либо ресурс или элемент не найден
class NotFoundException extends ACException {
  const NotFoundException();

  @override
  String localizedMessage([String? localeName]) =>
    _localization(localeName).notFoundException;
}

/// Исключение, когда обязательное поле не заполнено
class RequiredFieldException extends ACException {
  const RequiredFieldException();

  @override
  String localizedMessage([String? localeName]) =>
    _localization(localeName).requiredFieldException;
}

/// Исключение, когда длина введенного значения меньше минимальной
class MinLengthException extends ACException {
  const MinLengthException(
    this.minLength
  );

  final int minLength;

  @override
  String localizedMessage([String? localeName]) =>
    _localization(localeName).minLengthException(minLength);
}

/// Исключение, когда длина введенного значения превышает максимальную
class MaxLengthException extends ACException {
  const MaxLengthException(
    this.maxLength
  );

  final int maxLength;

  @override
  String localizedMessage([String? localeName]) =>
    _localization(localeName).maxLengthException(maxLength);
}

/// Исключение для неверного пароля
class WrongPasswordException extends ACException {
  const WrongPasswordException();

  @override
  String localizedMessage([String? localeName]) =>
    _localization(localeName).wrongPasswordException;
}

/// Исключение для неверного логина
final class WrongLoginException extends ACException {
  const WrongLoginException();

  @override
  String localizedMessage([String? localeName]) =>
    _localization(localeName).wrongLoginException;
}

/// Исключение для неверного email
final class WrongEmailException extends ACException {
  const WrongEmailException();

  @override
  String localizedMessage([String? localeName]) =>
    _localization(localeName).wrongEmailException;
}

/// Исключение для неавторизованных действий
final class UnauthorizedException extends ACException {
  const UnauthorizedException();

  @override
  String localizedMessage([String? localeName]) =>
    _localization(localeName).unauthorizedException;
}