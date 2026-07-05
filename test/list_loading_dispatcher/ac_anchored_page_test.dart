// ignore_for_file: prefer_const_constructors
import 'package:appcraft_list_loading_flutter/appcraft_list_loading_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

/// Around-page DTO mixing in [ACAnchoredPage]. Unlike a per-side `ACPage`, it
/// carries both directional flags (`hasMoreOlder`/`hasMoreNewer`) at once.
final class _Around with ACAnchoredPage<int> {
  const _Around({
    required this.items,
    required this.hasMoreOlder,
    required this.hasMoreNewer,
  });

  @override
  final List<int> items;
  @override
  final bool hasMoreOlder;
  @override
  final bool hasMoreNewer;
}

void main() {
  group('ACAnchoredPage — DTO exposes the three members', () {
    test('dtoWithItemsAndBothFlags_exposesItemsHasMoreOlderHasMoreNewer', () {
      // Arrange
      const page = _Around(
        items: <int>[1, 2, 3],
        hasMoreOlder: true,
        hasMoreNewer: false,
      );

      // Act & Assert — the mixin surfaces the raw model values.
      expect(page.items, equals(<int>[1, 2, 3]));
      expect(page.hasMoreOlder, isTrue);
      expect(page.hasMoreNewer, isFalse);
    });

    test('dtoIsAnAcAnchoredPage', () {
      // Arrange
      const page = _Around(
        items: <int>[],
        hasMoreOlder: false,
        hasMoreNewer: false,
      );

      // Act & Assert
      expect(page, isA<ACAnchoredPage<int>>());
    });

    test('emptyDto_reportsEmptyItemsAndFalseFlags', () {
      // Arrange
      const page = _Around(
        items: <int>[],
        hasMoreOlder: false,
        hasMoreNewer: false,
      );

      // Act & Assert
      expect(page.items, isEmpty);
      expect(page.hasMoreOlder, isFalse);
      expect(page.hasMoreNewer, isFalse);
    });
  });
}
