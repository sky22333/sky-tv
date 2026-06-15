import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../core/models/media_models.dart';
import '../../core/models/video_source.dart';
import '../../data/repositories/app_providers.dart';
import '../../ui/widgets/app_dialogs.dart';
import '../../ui/widgets/poster_row.dart';
import '../../ui/widgets/state_views.dart';

class SourcesPage extends ConsumerStatefulWidget {
  const SourcesPage({super.key});

  @override
  ConsumerState<SourcesPage> createState() => _SourcesPageState();
}

class _SourcesPageState extends ConsumerState<SourcesPage> {
  String? _selectedSourceId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_refreshSubscriptions());
    });
  }

  Future<void> _refreshSubscriptions() async {
    final repo = await ref.read(sourceRepositoryProvider.future);
    await repo.refreshDueSubscriptions().catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final sources = ref.watch(sourcesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('影视'),
        actions: [
          IconButton(
            onPressed: sources.maybeWhen(
              data: (items) => items.isEmpty ? null : _showManageSheet,
              orElse: () => null,
            ),
            icon: const Icon(Icons.tune_rounded),
            tooltip: '源管理',
          ),
        ],
      ),
      body: sources.when(
        data: (items) {
          if (items.isEmpty) {
            return EmptyState(
              icon: Icons.movie_filter_rounded,
              title: '还没有影视源',
              message: '导入 JSON 影视源后即可浏览和播放。',
              action: FilledButton.icon(
                onPressed: () => unawaited(_importSources()),
                icon: const Icon(Icons.add_rounded),
                label: const Text('导入影视源'),
              ),
            );
          }
          final mediaRepo = ref
              .watch(mediaRepositoryProvider)
              .maybeWhen(data: (repo) => repo, orElse: () => null);
          final enabled =
              mediaRepo?.enabledSources(items) ?? const <VideoSource>[];
          _syncSelectedSource(enabled);
          return LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 1000;
              if (wide) {
                return _DesktopBrowse(
                  sources: items,
                  enabled: enabled,
                  selectedSourceId: _selectedSourceId,
                  onSourceSelected: (value) =>
                      setState(() => _selectedSourceId = value),
                  onManage: _showManageSheet,
                  onRefresh: () => _refreshBrowse(),
                  onOpenDetail: (item) =>
                      context.push(SkyRoutes.detail(item.sourceId, item.id)),
                  onOpenCategory: (sourceId, categoryId) =>
                      context.push(SkyRoutes.category(sourceId, categoryId)),
                );
              }
              return _MobileBrowse(
                enabled: enabled,
                selectedSourceId: _selectedSourceId,
                onSourceSelected: (value) =>
                    setState(() => _selectedSourceId = value),
                onManage: _showManageSheet,
                onRefresh: () => _refreshBrowse(),
                onOpenDetail: (item) =>
                    context.push(SkyRoutes.detail(item.sourceId, item.id)),
                onOpenCategory: (sourceId, categoryId) =>
                    context.push(SkyRoutes.category(sourceId, categoryId)),
              );
            },
          );
        },
        error: (error, _) => ErrorState(message: error.toString()),
        loading: () => const LoadingState(message: '正在读取影视源...'),
      ),
    );
  }

  void _syncSelectedSource(List<VideoSource> enabled) {
    if (enabled.isEmpty) {
      if (_selectedSourceId != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() => _selectedSourceId = null);
          }
        });
      }
      return;
    }
    final current = _selectedSourceId;
    final stillValid =
        current != null && enabled.any((s) => s.sourceId == current);
    if (!stillValid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _selectedSourceId = enabled.first.sourceId);
        }
      });
    }
  }

  Future<void> _refreshBrowse() async {
    final sourceId = _selectedSourceId;
    ref.invalidate(sourcesProvider);
    if (sourceId != null) {
      ref.invalidate(sourceCategoriesProvider(sourceId));
      ref.invalidate(categoryPreviewRowsProvider(sourceId));
    }
  }

  Future<void> _showManageSheet() {
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => _SourceManageSheet(
        onImport: () {
          Navigator.pop(sheetContext);
          unawaited(_importSources());
        },
      ),
    );
  }

  Future<void> _importSources() async {
    final result = await showAppTextInputDialog(
      context,
      title: '导入影视源',
      hintText: '粘贴订阅 URL，或 JSON 数组',
      confirmText: '导入',
      minLines: 8,
      maxLines: 12,
      width: 560,
    );
    if (result == null || result.trim().isEmpty || !mounted) {
      return;
    }
    try {
      showBlockingProgressDialog(context, '正在导入...');
      final repo = await ref.read(sourceRepositoryProvider.future);
      if (!mounted) {
        return;
      }
      final value = result.trim();
      final importResult =
          value.startsWith('http://') || value.startsWith('https://')
          ? await repo.importSubscriptionUrl('远程订阅', value)
          : repo.importJson(value);
      if (!mounted) {
        return;
      }
      ref.invalidate(sourcesProvider);
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            importResult.sources.isEmpty && importResult.errors.isEmpty
                ? '订阅源无变化'
                : '导入 ${importResult.sources.length} 个源，错误 ${importResult.errors.length} 个',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }
}

class _MobileBrowse extends ConsumerWidget {
  const _MobileBrowse({
    required this.enabled,
    required this.selectedSourceId,
    required this.onSourceSelected,
    required this.onManage,
    required this.onRefresh,
    required this.onOpenDetail,
    required this.onOpenCategory,
  });

  final List<VideoSource> enabled;
  final String? selectedSourceId;
  final ValueChanged<String> onSourceSelected;
  final VoidCallback onManage;
  final Future<void> Function() onRefresh;
  final ValueChanged<MediaItem> onOpenDetail;
  final void Function(String sourceId, String categoryId) onOpenCategory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (enabled.isEmpty) {
      return EmptyState(
        icon: Icons.toggle_off_rounded,
        title: '还没有启用的影视源',
        message: '在源管理中启用影视源后即可浏览分类内容。',
        action: FilledButton(onPressed: onManage, child: const Text('打开源管理')),
      );
    }
    final sourceId = selectedSourceId ?? enabled.first.sourceId;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: _SourceChipRow(
                sources: enabled,
                selectedId: sourceId,
                onSelected: onSourceSelected,
              ),
            ),
          ),
          ..._BrowseContent(
            sourceId: sourceId,
            crossAxisCount: 2,
            onOpenDetail: onOpenDetail,
            onOpenCategory: onOpenCategory,
          ).buildSlivers(context, ref),
        ],
      ),
    );
  }
}

class _DesktopBrowse extends ConsumerWidget {
  const _DesktopBrowse({
    required this.sources,
    required this.enabled,
    required this.selectedSourceId,
    required this.onSourceSelected,
    required this.onManage,
    required this.onRefresh,
    required this.onOpenDetail,
    required this.onOpenCategory,
  });

  final List<VideoSource> sources;
  final List<VideoSource> enabled;
  final String? selectedSourceId;
  final ValueChanged<String> onSourceSelected;
  final VoidCallback onManage;
  final Future<void> Function() onRefresh;
  final ValueChanged<MediaItem> onOpenDetail;
  final void Function(String sourceId, String categoryId) onOpenCategory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sourceId = selectedSourceId;
    final mediaRepo = ref
        .watch(mediaRepositoryProvider)
        .maybeWhen(data: (repo) => repo, orElse: () => null);
    final ordered = mediaRepo?.orderedSources(sources) ?? sources;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 280,
          child: ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: [
                Text(
                  '我的源',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                for (final source in ordered) ...[
                  _SourceRailTile(
                    source: source,
                    selected: source.sourceId == sourceId,
                    onTap: source.disabled
                        ? null
                        : () => onSourceSelected(source.sourceId),
                  ),
                  const SizedBox(height: 8),
                ],
                IconButton(
                  onPressed: onManage,
                  icon: const Icon(Icons.tune_rounded),
                  tooltip: '源管理',
                ),
              ],
            ),
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: enabled.isEmpty || sourceId == null
              ? EmptyState(
                  icon: Icons.toggle_off_rounded,
                  title: '还没有启用的影视源',
                  message: '在左侧源管理中启用影视源后即可浏览分类内容。',
                  action: FilledButton(
                    onPressed: onManage,
                    child: const Text('打开源管理'),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: onRefresh,
                  child: CustomScrollView(
                    slivers: _BrowseContent(
                      sourceId: sourceId,
                      crossAxisCount: 4,
                      onOpenDetail: onOpenDetail,
                      onOpenCategory: onOpenCategory,
                    ).buildSlivers(context, ref),
                  ),
                ),
        ),
      ],
    );
  }
}

class _BrowseContent {
  const _BrowseContent({
    required this.sourceId,
    required this.crossAxisCount,
    required this.onOpenDetail,
    required this.onOpenCategory,
  });

  final String sourceId;
  final int crossAxisCount;
  final ValueChanged<MediaItem> onOpenDetail;
  final void Function(String sourceId, String categoryId) onOpenCategory;

  List<Widget> buildSlivers(BuildContext context, WidgetRef ref) {
    final previews = ref.watch(categoryPreviewRowsProvider(sourceId));
    final categories = ref.watch(sourceCategoriesProvider(sourceId));
    return [
      ...previews.when(
        data: (rows) {
          final visible = rows.where((row) => row.items.isNotEmpty).toList();
          if (visible.isEmpty) {
            return [
              const SliverToBoxAdapter(
                child: SizedBox(
                  height: 120,
                  child: EmptyState(
                    icon: Icons.movie_outlined,
                    title: '暂无预览内容',
                    message: '可进入下方分类继续浏览。',
                    compact: true,
                  ),
                ),
              ),
            ];
          }
          return [
            for (final row in visible) ...[
              SliverToBoxAdapter(
                child: SectionHeader(
                  title: row.category.name,
                  action: TextButton(
                    onPressed: () =>
                        onOpenCategory(row.category.sourceId, row.category.id),
                    child: const Text('全部'),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: PosterRow(items: row.items, onTap: onOpenDetail),
              ),
            ],
          ];
        },
        error: (error, _) => [
          SliverToBoxAdapter(
            child: ErrorState(
              message: error.toString(),
              onRetry: () {
                ref.invalidate(categoryPreviewRowsProvider(sourceId));
                ref.invalidate(sourceCategoriesProvider(sourceId));
              },
            ),
          ),
        ],
        loading: () => [
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: LoadingState(message: '正在加载分类预览...'),
            ),
          ),
        ],
      ),
      SliverToBoxAdapter(child: SectionHeader(title: '全部分类')),
      ...categories.when(
        data: (items) {
          if (items.isEmpty) {
            return [
              const SliverToBoxAdapter(
                child: SizedBox(
                  height: 160,
                  child: EmptyState(
                    icon: Icons.category_outlined,
                    title: '暂无分类',
                    message: '当前源没有返回分类列表。',
                    compact: true,
                  ),
                ),
              ),
            ];
          }
          return [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  mainAxisExtent: 52,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemBuilder: (context, index) {
                  final category = items[index];
                  return _CategoryTile(
                    name: category.name,
                    onTap: () => onOpenCategory(category.sourceId, category.id),
                  );
                },
                itemCount: items.length,
              ),
            ),
          ];
        },
        error: (error, _) => [
          SliverToBoxAdapter(
            child: ErrorState(
              message: error.toString(),
              onRetry: () => ref.invalidate(sourceCategoriesProvider(sourceId)),
            ),
          ),
        ],
        loading: () => [
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: LoadingState(message: '正在加载分类...'),
            ),
          ),
        ],
      ),
    ];
  }
}

class _SourceChipRow extends StatelessWidget {
  const _SourceChipRow({
    required this.sources,
    required this.selectedId,
    required this.onSelected,
  });

  final List<VideoSource> sources;
  final String selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, index) {
          final source = sources[index];
          return ChoiceChip(
            label: Text(source.name),
            selected: source.sourceId == selectedId,
            showCheckmark: false,
            onSelected: (_) => onSelected(source.sourceId),
          );
        },
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemCount: sources.length,
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.name, required this.onTap});

  final String name;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: scheme.onSurfaceVariant,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceRailTile extends StatelessWidget {
  const _SourceRailTile({
    required this.source,
    required this.selected,
    required this.onTap,
  });

  final VideoSource source;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? scheme.primaryContainer.withValues(alpha: 0.45)
          : scheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      source.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  if (source.disabled)
                    Text(
                      '已禁用',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              _LatencyBadge(text: _latencyText(source)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceManageSheet extends ConsumerStatefulWidget {
  const _SourceManageSheet({required this.onImport});

  final VoidCallback onImport;

  @override
  ConsumerState<_SourceManageSheet> createState() => _SourceManageSheetState();
}

class _SourceManageSheetState extends ConsumerState<_SourceManageSheet> {
  bool _testing = false;

  @override
  Widget build(BuildContext context) {
    final sourcesAsync = ref.watch(sourcesProvider);
    final mediaRepo = ref
        .watch(mediaRepositoryProvider)
        .maybeWhen(data: (repo) => repo, orElse: () => null);
    return sourcesAsync.when(
      data: (sources) {
        final ordered = mediaRepo?.orderedSources(sources) ?? sources;
        final enabled = ordered.where((source) => !source.disabled).length;
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * 0.72,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 8, 0),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(left: 8),
                          child: Text(
                            '源管理',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _testing
                            ? null
                            : () => unawaited(_testLatencies()),
                        tooltip: '全部测速',
                        icon: _testing
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.bolt_rounded),
                      ),
                      IconButton(
                        onPressed: widget.onImport,
                        tooltip: '导入影视源',
                        icon: const Icon(Icons.add_rounded),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    '共 ${ordered.length} 个源，已启用 $enabled 个',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ordered.isEmpty
                      ? const EmptyState(
                          icon: Icons.movie_filter_rounded,
                          title: '还没有影视源',
                          message: '导入后即可管理。',
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          itemBuilder: (context, index) {
                            final source = ordered[index];
                            return _ManageSourceTile(
                              source: source,
                              onDelete: () => unawaited(_confirmDelete(source)),
                              onEnabledChanged: (enabled) =>
                                  unawaited(_setEnabled(source, enabled)),
                            );
                          },
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemCount: ordered.length,
                        ),
                ),
              ],
            ),
          ),
        );
      },
      error: (error, _) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.4,
        child: ErrorState(message: error.toString()),
      ),
      loading: () => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.4,
        child: const LoadingState(message: '正在读取影视源...'),
      ),
    );
  }

  Future<void> _testLatencies() async {
    if (_testing) {
      return;
    }
    final sources = ref
        .read(sourcesProvider)
        .maybeWhen(data: (items) => items, orElse: () => const <VideoSource>[]);
    final enabledCount = sources.where((source) => !source.disabled).length;
    if (enabledCount == 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('没有已启用的影视源')));
      return;
    }
    setState(() => _testing = true);
    try {
      final repo = await ref.read(sourceRepositoryProvider.future);
      final result = await repo.testLatencies(sources);
      if (!mounted) {
        return;
      }
      ref.invalidate(sourcesProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('测速完成：${result.succeeded}/${result.total} 可用')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) {
        setState(() => _testing = false);
      }
    }
  }

  Future<void> _setEnabled(VideoSource source, bool enabled) async {
    final repo = await ref.read(sourceRepositoryProvider.future);
    if (!mounted) {
      return;
    }
    repo.setDisabled(source.sourceId, !enabled);
    ref.invalidate(sourcesProvider);
  }

  Future<void> _confirmDelete(VideoSource source) async {
    final confirmed = await confirmActionDialog(
      context,
      title: '删除影视源',
      message: '确定删除“${source.name}”吗？相关分类缓存也会一并清理。',
      confirmText: '删除',
    );
    if (!confirmed || !mounted) {
      return;
    }
    final repo = await ref.read(sourceRepositoryProvider.future);
    if (!mounted) {
      return;
    }
    repo.delete(source.sourceId);
    ref.invalidate(sourcesProvider);
  }
}

class _ManageSourceTile extends StatelessWidget {
  const _ManageSourceTile({
    required this.source,
    required this.onDelete,
    required this.onEnabledChanged,
  });

  final VideoSource source;
  final VoidCallback onDelete;
  final ValueChanged<bool> onEnabledChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
        child: Row(
          children: [
            PopupMenuButton<String>(
              tooltip: '更多',
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'delete', child: Text('删除')),
              ],
              onSelected: (value) {
                if (value == 'delete') {
                  onDelete();
                }
              },
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.more_vert_rounded),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    source.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    source.apiUrl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _LatencyBadge(text: _latencyText(source)),
                ],
              ),
            ),
            Switch(
              value: !source.disabled,
              onChanged: onEnabledChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
      ),
    );
  }
}

class _LatencyBadge extends StatelessWidget {
  const _LatencyBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, color: scheme.onPrimaryContainer),
        ),
      ),
    );
  }
}

String _latencyText(VideoSource source) {
  if (source.avgLatencyMs > 0) {
    return '${source.avgLatencyMs}ms · ${_relativeTime(source.lastSuccessAt)}';
  }
  if (source.lastFailureAt != null) {
    return '测速失败 · ${_relativeTime(source.lastFailureAt)}';
  }
  return '未测速';
}

String _relativeTime(DateTime? time) {
  if (time == null) {
    return '刚刚';
  }
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) {
    return '刚刚';
  }
  if (diff.inHours < 1) {
    return '${diff.inMinutes} 分钟前';
  }
  if (diff.inDays < 1) {
    return '${diff.inHours} 小时前';
  }
  return '${diff.inDays} 天前';
}
