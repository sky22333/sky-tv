import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../app/routes.dart';
import '../../core/models/media_models.dart';
import '../../data/repositories/app_providers.dart';
import '../../ui/widgets/poster_card.dart';
import '../../ui/widgets/poster_fallback.dart';
import '../../ui/widgets/poster_row.dart';
import '../../ui/widgets/app_logo.dart';
import '../../ui/widgets/state_views.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(homeDataProvider);
    return Scaffold(
      appBar: AppBar(
        title: const AppBrandTitle(),
        actions: [
          IconButton(
            onPressed: () => context.go('/search'),
            icon: const Icon(Icons.search_rounded),
            tooltip: '搜索',
          ),
        ],
      ),
      body: data.when(
        skipLoadingOnReload: true,
        data: (home) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(homeDataProvider);
            ref.invalidate(homeRecommendProvider);
          },
          child: ListView(
            children: [
              const SizedBox(height: 6),
              _HeroSearch(onTap: () => context.go('/search')),
              const _HomeRecommend(),
              SectionHeader(
                title: '继续观看',
                action: TextButton(
                  onPressed: () => context.go('/search'),
                  child: const Text('找片'),
                ),
              ),
              if (home.records.isEmpty)
                const SizedBox(
                  height: 160,
                  child: EmptyState(
                    icon: Icons.play_circle_outline,
                    title: '还没有播放记录',
                    message: '搜索影片并播放后，会在这里继续观看。',
                    compact: true,
                  ),
                )
              else
                ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemBuilder: (context, index) =>
                      _RecordTile(record: home.records[index]),
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemCount: home.records.length > 6 ? 6 : home.records.length,
                ),
              const SectionHeader(title: '我的收藏'),
              if (home.favorites.isEmpty)
                const SizedBox(
                  height: 140,
                  child: EmptyState(
                    icon: Icons.favorite_border,
                    title: '暂无收藏',
                    message: '喜欢的影片可以在详情页收藏。',
                    compact: true,
                  ),
                )
              else
                _PosterGrid(items: home.favorites),
              const SizedBox(height: 24),
            ],
          ),
        ),
        error: (error, _) => ErrorState(message: error.toString()),
        loading: () => const LoadingState(message: '正在读取本地数据...'),
      ),
    );
  }
}

class _HomeRecommend extends ConsumerWidget {
  const _HomeRecommend();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = ref.watch(sourcesProvider);
    final hasEnabled = sources.maybeWhen(
      data: (items) => items.any((source) => !source.disabled),
      orElse: () => false,
    );
    if (!hasEnabled) {
      return const SizedBox.shrink();
    }
    final recommend = ref.watch(homeRecommendProvider);
    return recommend.when(
      skipLoadingOnReload: true,
      data: (items) {
        if (items.isEmpty) {
          return const SizedBox.shrink();
        }
        return Column(
          children: [
            SectionHeader(
              title: '为你推荐',
              action: TextButton(
                onPressed: () => context.go('/sources'),
                child: const Text('更多'),
              ),
            ),
            PosterRow(
              items: items,
              onTap: (item) =>
                  context.push(SkyRoutes.detail(item.sourceId, item.id)),
            ),
            const SizedBox(height: 4),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}

class _HeroSearch extends StatelessWidget {
  const _HeroSearch({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Material(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(
                  Icons.search_rounded,
                  size: 22,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 12),
                Text(
                  '搜索影片',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecordTile extends StatelessWidget {
  const _RecordTile({required this.record});

  final WatchRecord record;

  @override
  Widget build(BuildContext context) {
    final progress = record.durationMs <= 0
        ? 0.0
        : (record.positionMs / record.durationMs).clamp(0.0, 1.0);
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () => context.push(
          SkyRoutes.player(
            record.sourceId,
            record.mediaId,
            lineIndex: record.lineIndex,
            episodeIndex: record.episodeIndex,
            resume: true,
          ),
        ),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 56,
                  height: 84,
                  child: record.poster == null
                      ? const PosterFallback()
                      : CachedNetworkImage(
                          imageUrl: record.poster!,
                          fit: BoxFit.cover,
                          placeholder: (_, _) => const PosterFallback(),
                          errorWidget: (_, _, _) => const PosterFallback(),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${record.sourceName} · 第 ${record.episodeIndex + 1} 集',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(value: progress),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.play_circle_fill_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PosterGrid extends StatelessWidget {
  const _PosterGrid({required this.items});

  final List<MediaItem> items;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: posterGridDelegate,
      itemBuilder: (context, index) {
        final item = items[index];
        return PosterCard(
          item: item,
          onTap: () => context.push(SkyRoutes.detail(item.sourceId, item.id)),
        );
      },
      itemCount: items.length,
    );
  }
}
