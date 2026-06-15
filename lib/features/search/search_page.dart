import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../app/routes.dart';
import '../../core/models/media_models.dart';
import '../../data/repositories/app_providers.dart';
import '../../data/repositories/media_repository.dart';
import '../../ui/widgets/app_search_field.dart';
import '../../ui/widgets/poster_fallback.dart';
import '../../ui/widgets/state_views.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key});

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _controller = TextEditingController();
  final _groups = <String, _SearchGroup>{};
  StreamSubscription<SearchEvent>? _subscription;
  bool _searching = false;
  bool _hasMoreSources = false;
  String? _error;
  int _searchToken = 0;
  int _searchedSourceCount = 0;
  int _enabledSourceCount = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final q = GoRouterState.of(context).uri.queryParameters['q'];
    if (q != null && q.isNotEmpty && _controller.text.isEmpty) {
      _controller.text = q;
      unawaited(_search(q));
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String keyword) async {
    final token = ++_searchToken;
    final value = keyword.trim();
    if (value.isEmpty) {
      if (!mounted) {
        return;
      }
      setState(() {
        _groups.clear();
        _searching = false;
        _hasMoreSources = false;
        _error = null;
        _searchedSourceCount = 0;
        _enabledSourceCount = 0;
      });
      return;
    }
    await _subscription?.cancel();
    if (!mounted || token != _searchToken) {
      return;
    }
    setState(() {
      _groups.clear();
      _searching = true;
      _hasMoreSources = false;
      _error = null;
      _searchedSourceCount = 0;
      _enabledSourceCount = 0;
    });
    await _searchNextBatch(value, token: token, saveRecent: true);
  }

  Future<void> _searchMore() async {
    if (_searching || !_hasMoreSources) {
      return;
    }
    final token = ++_searchToken;
    final value = _controller.text.trim();
    setState(() {
      _searching = true;
      _error = null;
    });
    await _searchNextBatch(value, token: token, saveRecent: false);
  }

  Future<void> _searchNextBatch(
    String value, {
    required int token,
    required bool saveRecent,
  }) async {
    try {
      final sourceRepoFuture = ref.read(sourceRepositoryProvider.future);
      final mediaRepoFuture = ref.read(mediaRepositoryProvider.future);
      final sourceRepo = await sourceRepoFuture;
      final mediaRepo = await mediaRepoFuture;
      if (!mounted || token != _searchToken) {
        return;
      }
      final sources = sourceRepo.sources();
      final enabledCount = mediaRepo.enabledSourceCount(sources);
      if (enabledCount == 0) {
        setState(() {
          _searching = false;
          _hasMoreSources = false;
          _error = '请先导入并启用影视源';
        });
        return;
      }
      _enabledSourceCount = enabledCount;
      final offset = _searchedSourceCount;
      final limit = MediaRepository.searchBatchSize;
      _subscription = mediaRepo
          .search(
            value,
            sources,
            offset: offset,
            limit: limit,
            saveRecent: saveRecent,
          )
          .listen((event) {
            if (!mounted || token != _searchToken) {
              return;
            }
            setState(() {
              switch (event) {
                case SourceSearchStarted(:final source):
                  _groups[source.sourceId] = _SearchGroup(
                    sourceName: source.name,
                  );
                case SourceSearchCompleted(:final source, :final items):
                  _groups[source.sourceId] = _SearchGroup(
                    sourceName: source.name,
                    items: items,
                    completed: true,
                  );
                case SourceSearchFailed(:final source, :final message):
                  _groups[source.sourceId] = _SearchGroup(
                    sourceName: source.name,
                    error: message,
                    completed: true,
                  );
                case SearchCompleted():
                  _searchedSourceCount = (offset + limit).clamp(
                    0,
                    enabledCount,
                  );
                  _hasMoreSources = _searchedSourceCount < enabledCount;
                  _searching = false;
              }
            });
          });
    } catch (error) {
      if (!mounted || token != _searchToken) {
        return;
      }
      setState(() {
        _searching = false;
        _hasMoreSources = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasResult = _groups.values.any((group) => group.items.isNotEmpty);
    final home = ref.watch(homeDataProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('搜索')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final width = math.min(constraints.maxWidth, 1120.0);
          return Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              width: width,
              height: constraints.maxHeight,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                    child: AppSearchField(
                      controller: _controller,
                      hintText: '搜索片名',
                      onSubmitted: _search,
                    ),
                  ),
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        if (_error != null) {
                          return ErrorState(
                            message: _error!,
                            onRetry: () => _search(_controller.text),
                          );
                        }
                        if (!_searching && _groups.isEmpty) {
                          return _SearchStartView(
                            keywords: home.maybeWhen(
                              data: (data) => data.recentSearches,
                              orElse: () => const [],
                            ),
                            onSearch: (keyword) {
                              _controller.text = keyword;
                              unawaited(_search(keyword));
                            },
                          );
                        }
                        if (!_searching && !hasResult && !_hasMoreSources) {
                          return const EmptyState(
                            icon: Icons.search_off_rounded,
                            title: '没有找到结果',
                            message: '可以换个关键词，或检查已启用的影视源。',
                          );
                        }
                        return ListView(
                          padding: const EdgeInsets.only(bottom: 24),
                          children: [
                            for (final group in _groups.values)
                              _SourceResultGroup(group: group),
                            if (_searching)
                              const Padding(
                                padding: EdgeInsets.all(20),
                                child: LoadingState(message: '正在搜索更多源...'),
                              ),
                            if (!_searching && _hasMoreSources)
                              _SearchMoreButton(
                                searched: _searchedSourceCount,
                                total: _enabledSourceCount,
                                onPressed: _searchMore,
                              ),
                            if (!_searching &&
                                !_hasMoreSources &&
                                _enabledSourceCount >
                                    MediaRepository.searchBatchSize)
                              const Padding(
                                padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
                                child: Center(child: Text('已搜索全部可用影视源')),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SearchMoreButton extends StatelessWidget {
  const _SearchMoreButton({
    required this.searched,
    required this.total,
    required this.onPressed,
  });

  final int searched;
  final int total;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.expand_more_rounded),
        label: Text('继续搜索更多源（$searched/$total）'),
      ),
    );
  }
}

class _SourceResultGroup extends StatelessWidget {
  const _SourceResultGroup({required this.group});

  final _SearchGroup group;

  @override
  Widget build(BuildContext context) {
    if (group.error != null) {
      return ExpansionTile(
        leading: const Icon(Icons.error_outline_rounded),
        title: Text(group.sourceName),
        subtitle: Text(
          group.error!,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        children: const [],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: group.sourceName),
        if (group.completed && group.items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
            child: InlineState(
              icon: Icons.search_off_rounded,
              title: '该源暂无结果',
              message: '继续等待其他源返回',
            ),
          ),
        if (!group.completed)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: LinearProgressIndicator(),
          ),
        for (final item in group.items) _SearchResultTile(item: item),
      ],
    );
  }
}

class _SearchStartView extends StatelessWidget {
  const _SearchStartView({required this.keywords, required this.onSearch});

  final List<String> keywords;
  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      children: [
        const EmptyState(
          icon: Icons.travel_explore_rounded,
          title: '搜索影片',
          message: '输入片名即可开始搜索。',
        ),
        if (keywords.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('最近搜索', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final keyword in keywords)
                ActionChip(
                  label: Text(keyword),
                  onPressed: () => onSearch(keyword),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  const _SearchResultTile({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      minVerticalPadding: 8,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 44,
          height: 66,
          child: item.poster == null
              ? const PosterFallback()
              : CachedNetworkImage(
                  imageUrl: item.poster!,
                  fit: BoxFit.cover,
                  memCacheWidth: 120,
                  placeholder: (_, _) => const PosterFallback(),
                  errorWidget: (_, _, _) => const PosterFallback(),
                ),
        ),
      ),
      title: Text(
        item.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        [
          item.year,
          item.category,
          item.sourceName,
        ].whereType<String>().join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => context.push(SkyRoutes.detail(item.sourceId, item.id)),
    );
  }
}

class _SearchGroup {
  const _SearchGroup({
    required this.sourceName,
    this.items = const [],
    this.error,
    this.completed = false,
  });

  final String sourceName;
  final List<MediaItem> items;
  final String? error;
  final bool completed;
}
