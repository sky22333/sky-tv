import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../data/repositories/app_providers.dart';
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
              else ...[
                ContinueWatchRow(
                  records: home.records,
                  onTap: (record) => context.push(
                    SkyRoutes.player(
                      record.sourceId,
                      record.mediaId,
                      lineIndex: record.lineIndex,
                      episodeIndex: record.episodeIndex,
                      resume: true,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
              ],
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
              else ...[
                PosterRow(
                  items: home.favorites,
                  onTap: (item) =>
                      context.push(SkyRoutes.detail(item.sourceId, item.id)),
                ),
                const SizedBox(height: 4),
              ],
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
