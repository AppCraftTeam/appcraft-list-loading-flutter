/// Базовый контракт параметров загрузки, принимаемых диспатчером списка.
///
/// Пользовательский тип параметров (передаваемый в `reload` и `loadMore`) должен
/// подмешать один из конкретных миксинов — [ACOffsetListLoadingParamsMixin] для
/// offset-пагинации или [ACCursorListLoadingParamsMixin] для cursor-пагинации, —
/// которые надстраиваются над этим базовым.
///
/// Базовый миксин несёт два поля:
/// - [limit] — информационное, диспатчер его не использует (оно нужно самому
///   loader'у при формировании запроса);
/// - [query] — читается диспатчером для `ACSearchStrategy` (debounce, minLength,
///   сброс при пустом значении).
///
/// Логики в миксине нет: это только декларация геттеров.
mixin ACListLoadingParamsMixin {
  /// Максимальное количество элементов, которое loader должен вернуть.
  ///
  /// Информационное поле: диспатчер его не читает. Рекомендуется значение
  /// `>= 0`; валидация остаётся на стороне потребителя.
  int? get limit;

  /// Поисковый запрос; основа поведения `ACSearchStrategy`.
  ///
  /// Диспатчер трактует `null` и пустую строку эквивалентно — как отсутствие
  /// поиска. Обрезка пробелов (trim) — ответственность потребителя.
  String? get query;
}

/// Параметры offset-пагинации.
///
/// Надстраивается над [ACListLoadingParamsMixin], добавляя поле [offset] —
/// смещение первой запрашиваемой записи. Диспатчер поле не читает; оно
/// предназначено для loader'а при формировании запроса к источнику.
///
/// Типичное использование:
///
/// ```dart
/// final class UserListParams
///     with ACListLoadingParamsMixin, ACOffsetListLoadingParamsMixin {
///   const UserListParams({this.offset, this.limit, this.query});
///
///   @override
///   final int? offset;
///   @override
///   final int? limit;
///   @override
///   final String? query;
/// }
/// ```
mixin ACOffsetListLoadingParamsMixin on ACListLoadingParamsMixin {
  /// Смещение (offset) для offset-based пагинации.
  ///
  /// Информационное поле: диспатчер его не читает. Рекомендуется значение
  /// `>= 0`; валидация остаётся на стороне потребителя.
  int? get offset;
}

/// Параметры cursor-пагинации.
///
/// Надстраивается над [ACListLoadingParamsMixin], добавляя поле [cursor] —
/// непрозрачный идентификатор следующей страницы, возвращаемый источником
/// данных в ответе. Диспатчер поле не читает; хранение актуального cursor
/// между вызовами `reload`/`loadMore` — ответственность потребителя.
///
/// Типичное использование:
///
/// ```dart
/// final class UserCursorParams
///     with ACListLoadingParamsMixin, ACCursorListLoadingParamsMixin {
///   const UserCursorParams({this.limit, this.cursor, this.query});
///
///   @override
///   final int? limit;
///   @override
///   final String? cursor;
///   @override
///   final String? query;
/// }
/// ```
mixin ACCursorListLoadingParamsMixin on ACListLoadingParamsMixin {
  /// Непрозрачный cursor следующей страницы (или `null` перед первой
  /// загрузкой / на последней странице).
  ///
  /// Информационное поле: диспатчер его не читает.
  String? get cursor;
}
