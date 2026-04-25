abstract class ACEntityMapper<Input, Output> {
  const ACEntityMapper();

  Output? map(Input? input);

  List<Output> mapList(List<Input?>? inputs) =>
    inputs?.map(map).whereType<Output>().toList() ?? [];

  Output mapNotNull(Input? input) {
    final output = map(input);

    if (output == null) throw Exception('Parsing error');
    return output;
  }
}
