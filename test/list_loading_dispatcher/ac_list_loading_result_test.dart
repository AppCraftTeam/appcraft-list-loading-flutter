import 'package:appcraft_list_loading_flutter/src/list_loading_dispatcher/src/ac_list_loading_result.dart';
import 'package:flutter_test/flutter_test.dart';

/// Minimal DTO that mixes in [ACListLoadingResult] — same shape users apply to
/// their response models.
final class _TestPage<T> with ACListLoadingResult<T> {
  const _TestPage({required this.items, required this.hasMore});

  @override
  final List<T> items;

  @override
  final bool hasMore;
}

void main() {
  group('ACListLoadingResult (mixin)', () {
    test('exposes items and hasMore from the mixing class', () {
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
      const stringPage = _TestPage<String>(items: <String>['a'], hasMore: false);

      // Act & Assert — typed getters stay typed through the mixin.
      expect(intPage.items, isA<List<int>>());
      expect(stringPage.items, isA<List<String>>());
    });

    test('instances satisfy ACListLoadingResult<T> subtype check', () {
      // Arrange
      const page = _TestPage<int>(items: <int>[1], hasMore: false);

      // Act & Assert
      expect(page, isA<ACListLoadingResult<int>>());
    });
  });
}
