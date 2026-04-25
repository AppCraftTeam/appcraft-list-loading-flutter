extension ACEnumByNameOrNull<T extends Enum> on Iterable<T> {
  
  T? byNameOrNull(String? name) {
    try {
      return byName(name ?? '');
    } on Object catch (_) {
      return null;
    }
  }

}

extension ACEnumComparisonOperators<T extends Enum> on T {
  bool operator <(T other) => index < other.index;

  bool operator <=(T other) => index <= other.index;

  bool operator >(T other) => index > other.index;

  bool operator >=(T other) => index >= other.index;
}