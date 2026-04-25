/// Миксин для объектов, которые имеют уникальный идентификатор [id].
mixin ACIdMixin {
  /// Уникальный идентификатор объекта
  String get id;
}

/// Расширение для списка объектов с миксином [ACIdMixin].
/// Позволяет удобно работать с элементами по их идентификатору.
extension ACIdMixinListExt<T extends ACIdMixin> on List<T> {

  /// Заменяет элемент в списке, если элемент с таким же id уже существует.
  /// Если элемент с таким id отсутствует — добавляет новый элемент в список.
  void setElementByID(T newElement) {
    final indexOfElement = indexWhere((e) => e.id == newElement.id);

    if (indexOfElement >= 0) {
      this[indexOfElement] = newElement;
    } else {
      add(newElement);
    }
  }

  /// Возвращает новый список с заменой/добавлением элемента по id.
  /// Исходный список при этом не изменяется.
  List<T> settedElementByID(T newElement) =>
    List.of(this)
      ..setElementByID(newElement);

  /// Удаляет элементы из списка, у которых id содержится в переданном наборе [ids].
  void removeElementByIDs(Set<String> ids) =>
    removeWhere((e) => ids.contains(e.id));

  /// Возвращает новый список с удалением элементов по id.
  /// Исходный список при этом не изменяется.
  List<T> removedElementByIDs(Set<String> ids) =>
    List.of(this)
      ..removeElementByIDs(ids);

}
