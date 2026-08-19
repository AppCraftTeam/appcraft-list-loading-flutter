import 'package:appcraft_list_loading_flutter/appcraft_list_loading_flutter.dart';
import 'package:flutter/material.dart';

void main() => runApp(const MaterialApp(home: HomeScreen()));

/// Demo screen: offset pagination + debounced search +
/// pull-to-refresh + infinite scroll.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  static const int _pageSize = 20;
  static const int _scrollLoadMoreThreshold = 200;

  late final ACListDispatcher<_DemoParams, String> _dispatcher;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _dispatcher = ACListDispatcher<_DemoParams, String>(
      searchStrategy: ACSearchDebouncer(
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
      appBar: AppBar(
        title: const Text('appcraft_list_loading_flutter'),
        actions: [
          IconButton(
            tooltip: 'Anchored chat demo',
            icon: const Icon(Icons.chat_bubble_outline),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AnchoredChatScreen(),
              ),
            ),
          ),
        ],
      ),
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

class _DemoParams with ACParamsMixin, ACOffsetParamsMixin {
  const _DemoParams({required this.limit, required this.offset, this.query});

  @override
  final int? limit;

  @override
  final int? offset;

  @override
  final String? query;
}


/// Demo screen: a chat opened **around** an anchor.
///
/// The window is composed by the caller out of two independent seeds —
/// [ACAnchoredDispatcher.reloadOlder] for the history above the anchor and
/// [ACAnchoredDispatcher.reloadNewer] for the anchor and everything below it.
/// The package does not couple the two calls: running them concurrently, and
/// the two requests it costs, are decisions made here.
class AnchoredChatScreen extends StatefulWidget {
  const AnchoredChatScreen({super.key});

  @override
  State<AnchoredChatScreen> createState() => _AnchoredChatScreenState();
}

class _AnchoredChatScreenState extends State<AnchoredChatScreen> {
  static const int _pageSize = 10;
  static const int _anchorId = 100;

  late final ACAnchoredDispatcher<_ChatParams, _ChatPage, String> _dispatcher;

  @override
  void initState() {
    super.initState();
    _dispatcher = ACAnchoredDispatcher<_ChatParams, _ChatPage, String>();
    _seedWindow();
  }

  @override
  void dispose() {
    _dispatcher.dispose();
    super.dispose();
  }

  /// Seeds both sides of the window around the anchor.
  ///
  /// Seeding only one side would leave the other as it was — after changing
  /// the anchor both sides must be seeded again.
  Future<void> _seedWindow() => Future.wait<void>([
        _dispatcher.reloadOlder(
          // closest-older -> oldest: the order loadOlder appends in too.
          params: const _ChatParams(cursor: _anchorId, older: true),
          load: _loadPage,
        ),
        _dispatcher.reloadNewer(
          // anchor -> newest: the anchor belongs to this side.
          params: const _ChatParams(cursor: _anchorId, older: false),
          load: _loadPage,
        ),
      ]);

  Future<_ChatPage> _loadPage(_ChatParams params) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final cursor = params.cursor;
    final step = params.older ? -1 : 1;
    // The older side skips the anchor itself — it lives on the newer side.
    final first = params.older ? cursor - 1 : cursor;
    return _ChatPage(
      items: List<String>.generate(
        _pageSize,
        (i) => 'Message ${first + i * step}',
      ),
      hasMore: params.older ? first - _pageSize > 0 : first + _pageSize < 140,
      nextCursor: first + _pageSize * step,
    );
  }

  Future<void> _loadOlder() => _dispatcher.loadOlder(
        params: _ChatParams(
          cursor: _dispatcher.lastResultOlder?.nextCursor ?? _anchorId,
          older: true,
        ),
        load: _loadPage,
      );

  Future<void> _loadNewer() => _dispatcher.loadNewer(
        params: _ChatParams(
          cursor: _dispatcher.lastResultNewer?.nextCursor ?? _anchorId,
          older: false,
        ),
        load: _loadPage,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Anchored chat')),
      body: ValueListenableBuilder<bool>(
        // True only while a side is being seeded — edge loads leave it false,
        // so the initial spinner does not flicker on scroll.
        valueListenable: _dispatcher.reloadingAnyListenable,
        builder: (context, isSeeding, _) {
          if (isSeeding) {
            return const Center(child: CircularProgressIndicator());
          }
          return ValueListenableBuilder<Object?>(
            valueListenable: _dispatcher.errorAnyListenable,
            builder: (context, error, _) {
              if (error != null) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('$error'),
                      TextButton(
                        onPressed: _seedWindow,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                );
              }
              return ListenableBuilder(
                listenable: _dispatcher,
                builder: (context, _) {
                  final items = _dispatcher.items;
                  return Column(
                    children: [
                      if (_dispatcher.hasMoreOlder)
                        TextButton(
                          onPressed: _loadOlder,
                          child: const Text('Load older'),
                        ),
                      Expanded(
                        child: ListView.builder(
                          itemCount: items.length,
                          itemBuilder: (_, i) => ListTile(
                            dense: true,
                            title: Text(items[i]),
                          ),
                        ),
                      ),
                      if (_dispatcher.hasMoreNewer)
                        TextButton(
                          onPressed: _loadNewer,
                          child: const Text('Load newer'),
                        ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _ChatParams with ACParamsMixin {
  const _ChatParams({required this.cursor, required this.older});

  final int cursor;
  final bool older;

  @override
  int? get limit => _AnchoredChatScreenState._pageSize;

  @override
  String? get query => null;
}

class _ChatPage with ACPage<String> {
  const _ChatPage({
    required this.items,
    required this.hasMore,
    required this.nextCursor,
  });

  @override
  final List<String> items;

  @override
  final bool hasMore;

  final int nextCursor;
}
