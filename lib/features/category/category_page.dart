import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../core/models/media_models.dart';
import '../../data/repositories/app_providers.dart';
import '../../ui/theme/app_system_ui.dart';
import '../../ui/widgets/poster_card.dart';
import '../../ui/widgets/state_views.dart';

class CategoryPage extends ConsumerStatefulWidget {
  const CategoryPage({
    super.key,
    required this.sourceId,
    required this.categoryId,
  });

  final String sourceId;
  final String categoryId;

  @override
  ConsumerState<CategoryPage> createState() => _CategoryPageState();
}

class _CategoryPageState extends ConsumerState<CategoryPage> {
  late Future<List<MediaItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  Widget build(BuildContext context) {
    return SystemUiRestorer(
      child: Scaffold(
        appBar: AppBar(title: const Text('分类')),
        body: SafeArea(
          top: false,
          child: FutureBuilder<List<MediaItem>>(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const LoadingState(message: '正在加载分类...');
              }
              if (snapshot.hasError) {
                return ErrorState(
                  message: snapshot.error.toString(),
                  onRetry: () => setState(() => _future = _load()),
                );
              }
              final items = snapshot.data ?? const [];
              if (items.isEmpty) {
                return const EmptyState(
                  icon: Icons.category_outlined,
                  title: '暂无内容',
                  message: '当前分类没有返回视频。',
                );
              }
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                gridDelegate: densePosterGridDelegate,
                itemBuilder: (context, index) {
                  final item = items[index];
                  return PosterCard(
                    item: item,
                    onTap: () =>
                        context.push(SkyRoutes.detail(item.sourceId, item.id)),
                  );
                },
                itemCount: items.length,
              );
            },
          ),
        ),
      ),
    );
  }

  Future<List<MediaItem>> _load() async {
    final sourceRepo = await ref.read(sourceRepositoryProvider.future);
    if (!mounted) {
      return const [];
    }
    final source = sourceRepo.findById(widget.sourceId);
    if (source == null) {
      throw Exception('影视源不存在');
    }
    final mediaRepo = await ref.read(mediaRepositoryProvider.future);
    if (!mounted) {
      return const [];
    }
    return mediaRepo.categoryVideos(source, widget.categoryId);
  }
}
