// ignore_for_file: prefer_const_constructors, unused_element_parameter
import 'package:appcraft_utils_flutter/src/list_loading_dispatcher/src/ac_list_loading_params.dart';
import 'package:appcraft_utils_flutter/src/list_loading_dispatcher/src/ac_list_loading_parser.dart';
import 'package:appcraft_utils_flutter/src/list_loading_dispatcher/src/ac_list_loading_result.dart';
import 'package:flutter_test/flutter_test.dart';

/// Offset-based params used to exercise [ACDefaultListLoadingParser].
final class _OffsetParams
    with ACListLoadingParamsMixin, ACOffsetListLoadingParamsMixin {
  const _OffsetParams({this.limit, this.offset, this.query});

  @override
  final int? limit;
  @override
  final int? offset;
  @override
  final String? query;
}

/// Base params used to exercise [ACResultListLoadingParser] (no pagination
/// fields needed — the parser delegates entirely to the result DTO).
final class _BaseParams with ACListLoadingParamsMixin {
  const _BaseParams({this.limit, this.query});

  @override
  final int? limit;
  @override
  final String? query;
}

/// Tiny DTO that mixes in [ACListLoadingResult] — mirrors the consumer pattern.
final class _TestPage<T> with ACListLoadingResult<T> {
  const _TestPage(this.items, {required this.hasMore});

  @override
  final List<T> items;
  @override
  final bool hasMore;
}

void main() {
  group('ACDefaultListLoadingParser', () {
    test('extractItems returns the input list as-is', () {
      // Arrange
      const parser = ACDefaultListLoadingParser<_OffsetParams, int>();
      const params = _OffsetParams(limit: 10, offset: 0);
      final result = <int>[1, 2, 3];

      // Act
      final items = parser.extractItems(params, result);

      // Assert
      expect(items, same(result),
          reason: 'default parser must return the bare list unchanged');
      expect(items, equals(<int>[1, 2, 3]));
    });

    test('extractItems returns an empty list as-is', () {
      // Arrange
      const parser = ACDefaultListLoadingParser<_OffsetParams, int>();
      const params = _OffsetParams(limit: 10);
      final result = <int>[];

      // Act
      final items = parser.extractItems(params, result);

      // Assert
      expect(items, same(result));
      expect(items, isEmpty);
    });

    test('hasMore: limit == null -> true regardless of result length', () {
      // Arrange
      const parser = ACDefaultListLoadingParser<_OffsetParams, int>();
      const params = _OffsetParams();

      // Act & Assert — empty page, nullable limit: still treat as "more".
      expect(parser.hasMore(params, <int>[]), isTrue);
      expect(parser.hasMore(params, <int>[1, 2, 3]), isTrue);
    });

    test('hasMore: result.length < limit -> false (last page)', () {
      // Arrange
      const parser = ACDefaultListLoadingParser<_OffsetParams, int>();
      const params = _OffsetParams(limit: 10);

      // Act & Assert
      expect(parser.hasMore(params, <int>[1, 2, 3]), isFalse);
      expect(parser.hasMore(params, <int>[]), isFalse);
    });

    test('hasMore: result.length == limit -> true (could be more)', () {
      // Arrange
      const parser = ACDefaultListLoadingParser<_OffsetParams, int>();
      const params = _OffsetParams(limit: 3);

      // Act
      final hasMore = parser.hasMore(params, <int>[1, 2, 3]);

      // Assert
      expect(hasMore, isTrue,
          reason: 'when the page is exactly full, more pages may exist');
    });

    test('hasMore: result.length > limit -> true (defensive, page overfull)',
        () {
      // Arrange
      const parser = ACDefaultListLoadingParser<_OffsetParams, int>();
      const params = _OffsetParams(limit: 2);

      // Act
      final hasMore = parser.hasMore(params, <int>[1, 2, 3]);

      // Assert
      expect(hasMore, isTrue);
    });

    test('implements ACListLoadingParser<P, List<T>, T>', () {
      // Arrange & Act
      const parser = ACDefaultListLoadingParser<_OffsetParams, int>();

      // Assert
      expect(
        parser,
        isA<ACListLoadingParser<_OffsetParams, List<int>, int>>(),
      );
    });
  });

  group('ACResultListLoadingParser', () {
    test('extractItems delegates to result.items', () {
      // Arrange
      const parser =
          ACResultListLoadingParser<_BaseParams, _TestPage<int>, int>();
      const params = _BaseParams();
      const result = _TestPage<int>(<int>[10, 20, 30], hasMore: true);

      // Act
      final items = parser.extractItems(params, result);

      // Assert
      expect(items, same(result.items));
      expect(items, equals(<int>[10, 20, 30]));
    });

    test('extractItems on an empty page returns empty list', () {
      // Arrange
      const parser =
          ACResultListLoadingParser<_BaseParams, _TestPage<int>, int>();
      const params = _BaseParams();
      const result = _TestPage<int>(<int>[], hasMore: false);

      // Act & Assert
      expect(parser.extractItems(params, result), isEmpty);
    });

    test('hasMore delegates to result.hasMore (true)', () {
      // Arrange
      const parser =
          ACResultListLoadingParser<_BaseParams, _TestPage<int>, int>();
      const params = _BaseParams();
      const result = _TestPage<int>(<int>[1], hasMore: true);

      // Act & Assert
      expect(parser.hasMore(params, result), isTrue);
    });

    test('hasMore delegates to result.hasMore (false)', () {
      // Arrange
      const parser =
          ACResultListLoadingParser<_BaseParams, _TestPage<int>, int>();
      const params = _BaseParams();
      const result = _TestPage<int>(<int>[1], hasMore: false);

      // Act & Assert
      expect(parser.hasMore(params, result), isFalse);
    });

    test('implements ACListLoadingParser<P, R, T>', () {
      // Arrange & Act
      const parser =
          ACResultListLoadingParser<_BaseParams, _TestPage<int>, int>();

      // Assert
      expect(
        parser,
        isA<ACListLoadingParser<_BaseParams, _TestPage<int>, int>>(),
      );
    });
  });
}
