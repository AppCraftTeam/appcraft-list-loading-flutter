import 'package:appcraft_list_loading_flutter/src/ac_page.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal DTO that mixes in [ACPage] — mirrors the pattern users apply to
/// their page-response models (`items` + `hasMore`).
final class _TestPage<T> with ACPage<T> {
  const _TestPage({required this.items, required this.hasMore});

  @override
  final List<T> items;

  @override
  final bool hasMore;
}

void main() {
  group('ACPage (mixin)', () {
    test('exposes items and hasMore from the mixing class (P-01)', () {
      // Arrange
      const page = _TestPage<int>(items: <int>[1, 2, 3], hasMore: true);

      // Act & Assert
      expect(page.items, equals(<int>[1, 2, 3]));
      expect(page.hasMore, isTrue);
    });

    test('supports an empty items list with hasMore=false', () {
      // Arrange
      const page = _TestPage<String>(items: <String>[], hasMore: false);

      // Act & Assert
      expect(page.items, isEmpty);
      expect(page.hasMore, isFalse);
    });

    test('is generic over the item type T', () {
      // Arrange
      const intPage = _TestPage<int>(items: <int>[42], hasMore: true);
      const stringPage =
          _TestPage<String>(items: <String>['a'], hasMore: false);

      // Act & Assert — typed getters stay typed through the mixin.
      expect(intPage.items, isA<List<int>>());
      expect(stringPage.items, isA<List<String>>());
    });

    test('instances satisfy ACPage<T> subtype check (P-02)', () {
      // Arrange
      const page = _TestPage<int>(items: <int>[1], hasMore: false);

      // Act & Assert
      expect(page, isA<ACPage<int>>());
    });
  });
}
