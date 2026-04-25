import '../../../appcraft_utils_flutter.dart';

/// Менеджер локализации.
class ACLocalizationManager {
  /// Приватный конструктор, чтобы предотвратить создание внешних экземпляров
  ACLocalizationManager._();

  /// Статический единственный экземпляр класса
  static final instance = ACLocalizationManager._();

  /// Словарь локализаций, где ключ — код языка, значение — объект локализации
  final Map<String, ACLocalization> localizations = {
    'ru': const ACLocalizationRu(),
    'en': const ACLocalizationEn()
  };

  /// Текущая локаль приложения (по умолчанию 'ru')
  String currentLocale = 'ru';

  /// Метод получения объекта локализации.
  /// Если [localeName] указан — возвращается локализация для него,
  /// иначе — текущая локаль. Если локаль не найдена — по умолчанию русская.
  ACLocalization localization([String? localeName]) =>
    localizations[localeName ?? currentLocale] ?? const ACLocalizationRu();
}