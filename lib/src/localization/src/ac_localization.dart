/// Абстрактный класс для локализации сообщений приложения.
/// Определяет набор обязательных сообщений и методов для конкретной локали.
abstract class ACLocalization {
  const ACLocalization();

  String get wipException;

  String get notFoundException;

  String get requiredFieldException;

  String get wrongPasswordException;

  String get wrongLoginException;

  String get wrongEmailException;

  String get unauthorizedException;

  String minLengthException(int minLength);

  String maxLengthException(int maxLength);
}

class ACLocalizationRu implements ACLocalization {
  const ACLocalizationRu();

  @override
  String get wipException =>
    'В разработке 👨‍💻';

  @override
  String get notFoundException =>
    'Ресурс не найден';
  
  @override
  String get requiredFieldException =>
    'Обязательное поле';

  @override
  String get wrongPasswordException =>
    'Некорректный пароль';

  @override
  String get wrongLoginException =>
    'Некорректный логин';

  @override
  String get wrongEmailException =>
    'Некорректный E-mail';

  @override
  String get unauthorizedException => 
    'Требуется авторизация';

  @override
  String minLengthException(int minLength) =>
    'Минимальная длина $minLength символов';

  @override
  String maxLengthException(int maxLength) =>
    'Длина превышает $maxLength символов';
}

class ACLocalizationEn implements ACLocalization {
  const ACLocalizationEn();

  @override
  String get wipException =>
    'In development 👨‍💻';

  @override
  String get notFoundException =>
    'Resource not found';

  @override
  String get requiredFieldException =>
    'Required field';

  @override
  String get wrongPasswordException =>
    'Wrong password';

  @override
  String get wrongLoginException =>
    'Wrong login';

  @override
  String get wrongEmailException =>
    'Wrong E-mail';

  @override
  String get unauthorizedException => 
    'Unauthorized';

  @override
  String minLengthException(int minLength) =>
    'Minimum length $minLength characters';

  @override
  String maxLengthException(int maxLength) =>
    'Length exceeds $maxLength characters';
  
}