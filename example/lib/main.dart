import 'package:appcraft_list_loading_flutter/appcraft_list_loading_flutter.dart';
import 'package:flutter/material.dart';

void main() => runApp(const MaterialApp(home: HomeScreen()));

/// Демонстрационный экран: offset-пагинация + поиск с debounce +
/// pull-to-refresh + infinite scroll.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  static const int _pageSize = 20;
  static const int _scrollLoadMoreThreshold = 200;

  late final ACDefaultListLoadingDispatcher<_DemoParams, String> _dispatcher;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _dispatcher = ACDefaultListLoadingDispatcher<_DemoParams, String>(
      searchStrategy: ACDebouncedSearchStrategy(
        debounce: const Duration(milliseconds: 300),
        minLength: 2,
      ),
    );
    _scrollController.addListener(_handleScroll);
    _dispatcher.reload(
      params: const _DemoParams(limit: _pageSize, offset: 0, query: ''),
      load: _loadItems,
    );
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    _searchController.dispose();
    _dispatcher.dispose();
    super.dispose();
  }

  Future<List<String>> _loadItems(_DemoParams params) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final query = params.query ?? '';
    return List<String>.generate(
      params.limit ?? _pageSize,
      (i) => 'Item ${(params.offset ?? 0) + i}'
          '${query.isEmpty ? '' : ' (query: $query)'}',
    );
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.extentAfter > _scrollLoadMoreThreshold) return;
    if (_dispatcher.isLoading) return;
    if (!_dispatcher.hasMore) return;

    _dispatcher.loadMore(
      params: _DemoParams(
        limit: _pageSize,
        offset: _dispatcher.items.length,
        query: _searchController.text,
      ),
      load: _loadItems,
    );
  }

  Future<void> _handleQueryChanged(String query) => _dispatcher.reload(
        params: _DemoParams(limit: _pageSize, offset: 0, query: query),
        load: _loadItems,
      );

  Future<void> _handleRefresh() => _dispatcher.reload(
        params: _DemoParams(
          limit: _pageSize,
          offset: 0,
          query: _searchController.text,
        ),
        load: _loadItems,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('appcraft_list_loading_flutter')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Search',
                border: OutlineInputBorder(),
              ),
              onChanged: _handleQueryChanged,
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _handleRefresh,
              child: ListenableBuilder(
                listenable: _dispatcher,
                builder: (context, _) {
                  final items = _dispatcher.items;
                  if (items.isEmpty) {
                    return ListView(
                      controller: _scrollController,
                      children: const [
                        SizedBox(height: 120),
                        Center(child: Text('No items')),
                      ],
                    );
                  }
                  return ListView.builder(
                    controller: _scrollController,
                    itemCount: items.length,
                    itemBuilder: (_, i) => ListTile(title: Text(items[i])),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DemoParams with ACListLoadingParamsMixin, ACOffsetListLoadingParamsMixin {
  const _DemoParams({required this.limit, required this.offset, this.query});

  @override
  final int? limit;

  @override
  final int? offset;

  @override
  final String? query;
}
