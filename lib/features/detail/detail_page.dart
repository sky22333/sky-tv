import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../core/models/media_models.dart';
import '../../data/repositories/app_providers.dart';
import '../../ui/theme/app_theme.dart';
import '../../ui/theme/app_system_ui.dart';
import '../../ui/widgets/poster_card.dart';
import '../../ui/widgets/state_views.dart';

class DetailPage extends ConsumerStatefulWidget {
  const DetailPage({super.key, required this.sourceId, required this.mediaId});

  final String sourceId;
  final String mediaId;

  @override
  ConsumerState<DetailPage> createState() => _DetailPageState();
}

class _DetailPageState extends ConsumerState<DetailPage> {
  late Future<MediaDetail?> _future;
  bool _isFavorite = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SystemUiRestorer(
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
          statusBarBrightness: dark ? Brightness.dark : Brightness.light,
        ),
        child: Scaffold(
          body: SafeArea(
            top: false,
            child: FutureBuilder<MediaDetail?>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const LoadingState(message: '正在加载详情...');
                }
                if (snapshot.hasError) {
                  return ErrorState(
                    message: snapshot.error.toString(),
                    onRetry: () => setState(() => _future = _load()),
                  );
                }
                final detail = snapshot.data;
                if (detail == null) {
                  return const EmptyState(
                    icon: Icons.movie_filter_outlined,
                    title: '没有详情',
                    message: '当前源没有返回该影片详情。',
                  );
                }
                return CustomScrollView(
                  slivers: [
                    SliverAppBar(
                      expandedHeight: 260,
                      pinned: true,
                      title: Text(
                        detail.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      actions: [
                        IconButton(
                          onPressed: () => _toggleFavorite(detail),
                          icon: Icon(
                            _isFavorite
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                          ),
                        ),
                      ],
                      flexibleSpace: FlexibleSpaceBar(
                        background: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                AppTheme.primary.withValues(alpha: 0.35),
                                Theme.of(context).colorScheme.surface,
                              ],
                            ),
                          ),
                          child: _DetailContentWidth(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                96,
                                20,
                                24,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  AspectRatio(
                                    aspectRatio: 2 / 3,
                                    child: LayoutBuilder(
                                      builder: (context, constraints) {
                                        return ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                          child: PosterImage(
                                            url: detail.poster,
                                            memCacheWidth: posterMemCacheFor(
                                              constraints.maxWidth,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 18),
                                  Expanded(
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          detail.title,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context)
                                              .textTheme
                                              .headlineSmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.w900,
                                              ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          [
                                            detail.year,
                                            detail.category,
                                            detail.sourceName,
                                          ].whereType<String>().join(' · '),
                                          style: TextStyle(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: _DetailContentWidth(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            detail.description?.isNotEmpty == true
                                ? detail.description!
                                : '暂无简介',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              height: 1.55,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (detail.playLines.isEmpty)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: InlineState(
                          icon: Icons.link_off_rounded,
                          title: '没有播放地址',
                          message: '当前详情没有返回可播放线路。',
                        ),
                      )
                    else
                      SliverList.builder(
                        itemCount: detail.playLines.length,
                        itemBuilder: (context, lineIndex) {
                          final line = detail.playLines[lineIndex];
                          return _DetailContentWidth(
                            child: _PlayLineBlock(
                              detail: detail,
                              line: line,
                              lineIndex: lineIndex,
                            ),
                          );
                        },
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Future<MediaDetail?> _load() async {
    final sourceRepo = await ref.read(sourceRepositoryProvider.future);
    if (!mounted) {
      return null;
    }
    final source = sourceRepo.findById(widget.sourceId);
    if (source == null) {
      throw Exception('影视源不存在');
    }
    final mediaRepo = await ref.read(mediaRepositoryProvider.future);
    if (!mounted) {
      return null;
    }
    final detail = await mediaRepo.detail(source, widget.mediaId);
    final favorite = mediaRepo.isFavorite(widget.sourceId, widget.mediaId);
    if (mounted) {
      setState(() => _isFavorite = favorite);
    }
    return detail;
  }

  Future<void> _toggleFavorite(MediaDetail detail) async {
    final repo = await ref.read(mediaRepositoryProvider.future);
    repo.toggleFavorite(detail);
    final favorite = repo.isFavorite(detail.sourceId, detail.id);
    if (!mounted) {
      return;
    }
    setState(() => _isFavorite = favorite);
    ref.invalidate(homeDataProvider);
    ref.invalidate(homeRecommendProvider);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(favorite ? '已收藏' : '已取消收藏')));
  }
}

class _DetailContentWidth extends StatelessWidget {
  const _DetailContentWidth({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: math.min(constraints.maxWidth, 1120),
          child: child,
        ),
      ),
    );
  }
}

class _PlayLineBlock extends StatelessWidget {
  const _PlayLineBlock({
    required this.detail,
    required this.line,
    required this.lineIndex,
  });

  final MediaDetail detail;
  final PlayLine line;
  final int lineIndex;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(line.name, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (var i = 0; i < line.episodes.length; i++)
                FilledButton.tonal(
                  onPressed: () => context.push(
                    SkyRoutes.player(
                      detail.sourceId,
                      detail.id,
                      lineIndex: lineIndex,
                      episodeIndex: i,
                    ),
                    extra: detail,
                  ),
                  child: Text(line.episodes[i].title),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
