import 'package:appcraft_list_loading_flutter/appcraft_list_loading_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('inheritance smoke (extends)', () {
    test('ACOperationCancelStrategy can be extended', () async {
      final s = _ExtCancel();
      expect(s.isActive, isFalse);
      await s.cancel(); // no-op safe
    });

    test('ACDefaultDispatcher can be extended', () async {
      final d = _ExtDefaultDispatcher<_Params, String>();
      await d.reload(
        params: const _Params(),
        load: (_) async => <String>[],
      );
      expect(d.items, isEmpty);
      d.dispose();
    });

    test('ACCustomDispatcher can be extended', () async {
      final d = _ExtCustomDispatcher<_Params, _DemoResult, String>();
      await d.reload(
        params: const _Params(),
        load: (_) async => _DemoResult(items: ['x'], hasMore: false),
      );
      expect(d.items, ['x']);
      d.dispose();
    });

    test('ACDefaultParser can be extended', () {
      const p = _ExtDefaultParser<_Params, String>();
      expect(p.extractItems(const _Params(), ['a']), ['a']);
    });

    test('ACResultParser can be extended', () {
      const p = _ExtResultParser<_Params, _DemoResult, String>();
      final result = _DemoResult(items: ['a'], hasMore: false);
      expect(p.extractItems(const _Params(), result), ['a']);
      expect(p.hasMore(const _Params(), result), isFalse);
    });

    test('ACDebouncedSearchStrategy can be extended', () async {
      final s = _ExtDebouncedSearch();
      // schedule с null query — мгновенное завершение
      final f = s.schedule(null);
      expect(f, isNotNull);
      await f;
      s.dispose();
    });
  });

  group('inheritance smoke (implements)', () {
    test('ACOperationCancelStrategy can be implemented', () async {
      final s = _ImplCancel();
      expect(s.isActive, isFalse);
      await s.cancel(); // no-op
      final result = await s.run<int>(Future.value(42));
      expect(result, 42);
    });

    test('ACDefaultDispatcher can be implemented', () {
      final d = _ImplDefaultDispatcher();
      expect(d.items, isEmpty);
      expect(d.isLoading, isFalse);
      expect(d.hasMore, isTrue);
      d.dispose();
    });

    test('ACCustomDispatcher can be implemented', () {
      final d = _ImplCustomDispatcher();
      expect(d.items, isEmpty);
      d.dispose();
    });

    test('ACDefaultParser can be implemented', () {
      const p = _ImplDefaultParser();
      expect(p.extractItems(const _Params(), [1, 2]), [1, 2]);
      expect(p.hasMore(const _Params(), [1, 2]), isFalse);
    });

    test('ACResultParser can be implemented', () {
      const p = _ImplResultParser();
      final r = _DemoResult(items: ['a'], hasMore: true);
      expect(p.extractItems(const _Params(), r), ['a']);
      expect(p.hasMore(const _Params(), r), isTrue);
    });

    test('ACDebouncedSearchStrategy can be implemented', () async {
      final s = _ImplDebouncedSearch();
      final f = s.schedule('q');
      expect(f, isNotNull);
      await f;
      s.dispose();
    });
  });
}

// =================================================================
// Helper params/result DTOs
// =================================================================

class _Params with ACParamsMixin, ACOffsetParamsMixin {
  const _Params();

  @override
  int? get limit => 10;

  @override
  int? get offset => 0;

  @override
  String? get query => null;
}

class _DemoResult with ACResult<String> {
  _DemoResult({required this.items, required this.hasMore});

  @override
  final List<String> items;

  @override
  final bool hasMore;
}

// =================================================================
// Top-level subclasses for compilation-level verification
// =================================================================

// extends-subclasses

class _ExtCancel extends ACOperationCancelStrategy {}

class _ExtDefaultDispatcher<P extends ACOffsetParamsMixin, T>
    extends ACDefaultDispatcher<P, T> {
  _ExtDefaultDispatcher({super.searchStrategy});
}

class _ExtCustomDispatcher<P extends ACParamsMixin,
        R extends ACResult<T>, T>
    extends ACCustomDispatcher<P, R, T> {
  _ExtCustomDispatcher({super.searchStrategy});
}

class _ExtDefaultParser<P extends ACOffsetParamsMixin, T>
    extends ACDefaultParser<P, T> {
  const _ExtDefaultParser();
}

class _ExtResultParser<P extends ACParamsMixin,
        R extends ACResult<T>, T>
    extends ACResultParser<P, R, T> {
  const _ExtResultParser();
}

class _ExtDebouncedSearch extends ACDebouncedSearchStrategy {}

// implements-subclasses

class _ImplCancel implements ACOperationCancelStrategy {
  @override
  bool get isActive => false;

  @override
  Future<void> cancel() async {}

  @override
  Future<T?> run<T>(Future<T> future) => future;
}

class _ImplDefaultDispatcher
    implements ACDefaultDispatcher<_Params, String> {
  @override
  final ACParser<_Params, List<String>, String> parser =
      const ACDefaultParser<_Params, String>();

  @override
  final ACSearchStrategy searchStrategy = ACDebouncedSearchStrategy();

  @override
  List<String> get items => const [];

  @override
  bool get isLoading => false;

  @override
  bool get hasMore => true;

  @override
  List<String>? get lastResult => null;

  @override
  bool get hasListeners => false;

  @override
  Future<void> reload({
    required _Params params,
    required Future<List<String>> Function(_Params params) load,
    ACCancelStrategy? cancelStrategy,
  }) async {}

  @override
  Future<void> loadMore({
    required _Params params,
    required Future<List<String>> Function(_Params params) load,
    ACCancelStrategy? cancelStrategy,
  }) async {}

  @override
  Future<void> cancel() async {}

  @override
  void dispose() {}

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}

  @override
  void notifyListeners() {}
}

class _ImplCustomDispatcher
    implements ACCustomDispatcher<_Params, _DemoResult, String> {
  @override
  final ACParser<_Params, _DemoResult, String> parser =
      const ACResultParser<_Params, _DemoResult, String>();

  @override
  final ACSearchStrategy searchStrategy = ACDebouncedSearchStrategy();

  @override
  List<String> get items => const [];

  @override
  bool get isLoading => false;

  @override
  bool get hasMore => true;

  @override
  _DemoResult? get lastResult => null;

  @override
  bool get hasListeners => false;

  @override
  Future<void> reload({
    required _Params params,
    required Future<_DemoResult> Function(_Params params) load,
    ACCancelStrategy? cancelStrategy,
  }) async {}

  @override
  Future<void> loadMore({
    required _Params params,
    required Future<_DemoResult> Function(_Params params) load,
    ACCancelStrategy? cancelStrategy,
  }) async {}

  @override
  Future<void> cancel() async {}

  @override
  void dispose() {}

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}

  @override
  void notifyListeners() {}
}

class _ImplDefaultParser
    implements ACDefaultParser<_Params, int> {
  const _ImplDefaultParser();

  @override
  List<int> extractItems(_Params params, List<int> result) => result;

  @override
  bool hasMore(_Params params, List<int> result) => false;
}

class _ImplResultParser
    implements ACResultParser<_Params, _DemoResult, String> {
  const _ImplResultParser();

  @override
  List<String> extractItems(_Params params, _DemoResult result) => result.items;

  @override
  bool hasMore(_Params params, _DemoResult result) => result.hasMore;
}

class _ImplDebouncedSearch implements ACDebouncedSearchStrategy {
  @override
  Duration get debounce => Duration.zero;

  @override
  int get minLength => 1;

  @override
  Future<void>? schedule(String? query) => Future<void>.value();

  @override
  void cancel() {}

  @override
  void dispose() {}
}
