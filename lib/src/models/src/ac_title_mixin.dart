/// Миксин для объектов, которые имеют заголовок [title].
mixin ACTitleMixin {

  /// Заголовок объекта
  String get title;
}

/// Класс-обертка для хранения заголовка.
/// Использует миксин [ACTitleMixin] для совместимости с расширениями.
class ACTitle with ACTitleMixin {

  /// Конструктор принимает обязательный заголовок [title]
  const ACTitle({
    required this.title
  });

  /// Поле заголовка
  final String title;
}

/// Расширение для списка объектов с миксином [ACTitleMixin].
/// Позволяет выполнять операции, связанные с заголовком.
extension TitleMixinListExt<T extends ACTitleMixin> on List<T> {

  /// Возвращает новый список, отсортированный по заголовку title в алфавитном порядке.
  /// Исходный список при этом не изменяется.
  List<T> sortedByTitle() =>
    List
      .of(this)
      ..sort((a, b) => a.title.compareTo(b.title));

}