import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../core/models/media_models.dart';
import '../../data/repositories/app_providers.dart';
import '../../ui/widgets/app_dialogs.dart';
import '../../ui/widgets/app_logo.dart';
import '../../ui/widgets/poster_row.dart';
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
            onPressed: () => context.go(SkyRoutes.search()),
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
              if (home.recentSearches.isNotEmpty)
                _RecentSearches(keywords: home.recentSearches),
              const _HomeRecommend(),
              SectionHeader(
                title: '继续观看',
                action: home.records.isEmpty
                    ? TextButton(
                        onPressed: () => context.go(SkyRoutes.search()),
                        child: const Text('找片'),
                      )
                    : null,
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
                  onLongPress: (record) =>
                      unawaited(_removeWatchRecord(context, ref, record)),
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
                  onLongPress: (item) =>
                      unawaited(_removeFavorite(context, ref, item)),
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

Future<void> _removeWatchRecord(
  BuildContext context,
  WidgetRef ref,
  WatchRecord record,
) async {
  final confirmed = await confirmActionDialog(
    context,
    title: '移除续看',
    message: '从继续观看中移除「${record.title}」？',
    confirmText: '移除',
  );
  if (!confirmed || !context.mounted) {
    return;
  }
  final repo = await ref.read(mediaRepositoryProvider.future);
  repo.deleteWatchRecord(record.sourceId, record.mediaId);
  ref.invalidate(homeDataProvider);
}

Future<void> _removeFavorite(
  BuildContext context,
  WidgetRef ref,
  MediaItem item,
) async {
  final confirmed = await confirmActionDialog(
    context,
    title: '取消收藏',
    message: '取消收藏「${item.title}」？',
    confirmText: '取消收藏',
  );
  if (!confirmed || !context.mounted) {
    return;
  }
  final repo = await ref.read(mediaRepositoryProvider.future);
  repo.toggleFavorite(item);
  ref.invalidate(homeDataProvider);
  ref.invalidate(homeRecommendProvider);
}

class _RecentSearches extends StatelessWidget {
  const _RecentSearches({required this.keywords});

  final List<String> keywords;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(title: '最近搜索'),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            itemCount: keywords.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final keyword = keywords[index];
              return ActionChip(
                label: Text(keyword),
                onPressed: () => context.go(SkyRoutes.search(keyword)),
              );
            },
          ),
        ),
      ],
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
