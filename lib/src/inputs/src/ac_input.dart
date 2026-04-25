import 'package:equatable/equatable.dart';

import '../../../appcraft_utils_flutter.dart';

/// Абстрактный класс для обработки ввода данных в форме
/// [V] — тип значения поля
/// [E] — тип ошибки валидации
abstract class ACInput<V, E> with ACInputMixin, EquatableMixin {

  /// Конструктор принимает:
  /// [value] — текущее значение поля
  /// [isPure] — флаг, указывающий, было ли значение изменено пользователем
  const ACInput({
    required this.value,
    this.isPure = true
  });

  /// Текущее значение поля
  final V value;

  /// Флаг, указывающий, было ли значение изменено пользователем
  /// true — значение не менялось,
  /// false — изменялось
  final bool isPure;

  /// Проверка валидности поля: true, если ошибок нет
  bool get isValid => validator(value) == null;

  /// Отображаемая ошибка:
  /// Если значение не менялось (isPure == true), ошибки не показываются
  E? get displayError => isPure ?
    null :
    validator(value);

  /// Проверка значения
  E? validator(V? value) => 
    validations(value)
    .validate(value);

  /// Список валидаций для поля. 
  /// По умолчанию пустой, переопределяется в конкретных имплементациях.
  List<ACValidation<V, E>> validations(V? value) => [];

  @override
  String toString() => 'ACInput(value: $value, isPure: $isPure)';

  @override
  List<Object?> get props => [
    value,
    isPure
  ];
}