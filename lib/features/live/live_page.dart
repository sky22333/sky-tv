import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../core/models/iptv_models.dart';
import '../../data/repositories/app_providers.dart';
import '../../ui/widgets/app_dialogs.dart';
import '../../ui/widgets/app_search_field.dart';
import '../../ui/widgets/state_views.dart';
import 'live_channel_tile.dart';
import 'live_group_selector.dart';

class LivePage extends ConsumerStatefulWidget {
  const LivePage({super.key});

  @override
  ConsumerState<LivePage> createState() => _LivePageState();
}

class _LivePageState extends ConsumerState<LivePage> {
  static const _searchDebounce = Duration(milliseconds: 300);

  String? _group;
  String _keyword = '';
  Timer? _searchTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_refreshSubscriptions());
    });
  }

  Future<void> _refreshSubscriptions() async {
    final repo = await ref.read(iptvRepositoryProvider.future);
    await repo.refreshDueSubscriptions().catchError((_) {});
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _searchTimer?.cancel();
    _searchTimer = Timer(_searchDebounce, () {
      if (!mounted) {
        return;
      }
      setState(() => _keyword = value.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(iptvLibraryProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('直播'),
        actions: [
          IconButton(
            onPressed: () => _showSubscriptions(context),
            icon: const Icon(Icons.playlist_play_rounded),
            tooltip: '订阅管理',
          ),
          IconButton(
            onPressed: () => _showImportDialog(context),
            icon: const Icon(Icons.add_rounded),
            tooltip: '导入 IPTV',
          ),
        ],
      ),
      body: library.when(
        data: (data) {
          final channels = _filterChannels(data.channels);
          if (data.channels.isEmpty && data.subscriptions.isEmpty) {
            return EmptyState(
              icon: Icons.live_tv_rounded,
              title: '还没有直播源',
              message: '导入 m3u、m3u8、txt 或 JSON 订阅后即可观看。',
              action: FilledButton.icon(
                onPressed: () => _showImportDialog(context),
                icon: const Icon(Icons.add_rounded),
                label: const Text('导入直播源'),
              ),
            );
          }
          return LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 1000;
              return RefreshIndicator(
                onRefresh: () async => ref.invalidate(iptvLibraryProvider),
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: _LiveToolbar(
                        groups: data.groups,
                        group: _group,
                        onGroupChanged: (value) =>
                            setState(() => _group = value),
                        onSearchChanged: _onSearchChanged,
                      ),
                    ),
                    if (channels.isEmpty)
                      const SliverFillRemaining(
                        hasScrollBody: false,
                        child: EmptyState(
                          icon: Icons.search_off_rounded,
                          title: '没有匹配频道',
                          message: '换个分组或关键词再试。',
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        sliver: wide
                            ? SliverGrid.builder(
                                gridDelegate:
                                    const SliverGridDelegateWithMaxCrossAxisExtent(
                                      maxCrossAxisExtent: 360,
                                      mainAxisExtent: 76,
                                      crossAxisSpacing: 10,
                                      mainAxisSpacing: 10,
                                    ),
                                itemBuilder: (context, index) =>
                                    LiveChannelTile(
                                      channel: channels[index],
                                      onTap: () => context.push(
                                        SkyRoutes.live(channels[index].id),
                                      ),
                                    ),
                                itemCount: channels.length,
                              )
                            : SliverList.separated(
                                itemBuilder: (context, index) =>
                                    LiveChannelTile(
                                      channel: channels[index],
                                      onTap: () => context.push(
                                        SkyRoutes.live(channels[index].id),
                                      ),
                                    ),
                                separatorBuilder: (_, _) =>
                                    const SizedBox(height: 8),
                                itemCount: channels.length,
                              ),
                      ),
                  ],
                ),
              );
            },
          );
        },
        error: (error, _) => ErrorState(message: error.toString()),
        loading: () => const LoadingState(message: '正在读取直播频道...'),
      ),
    );
  }

  List<IptvChannel> _filterChannels(List<IptvChannel> channels) {
    final group = _group;
    final keyword = _keyword;
    if (group == null && keyword.isEmpty) {
      return channels;
    }
    return channels.where((channel) {
      final matchesGroup = group == null || channel.group == group;
      final matchesKeyword = keyword.isEmpty || channel.name.contains(keyword);
      return matchesGroup && matchesKeyword;
    }).toList();
  }

  Future<void> _showSubscriptions(BuildContext context) async {
    final repo = await ref.read(iptvRepositoryProvider.future);
    if (!context.mounted) {
      return;
    }
    final library = repo.library();
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.58,
          child: library.subscriptions.isEmpty
              ? const EmptyState(
                  icon: Icons.playlist_remove_rounded,
                  title: '还没有订阅',
                  message: '导入直播源后会显示在这里。',
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemBuilder: (context, index) {
                    final subscription = library.subscriptions[index];
                    return ListTile(
                      leading: const Icon(Icons.live_tv_rounded),
                      title: Text(
                        subscription.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        subscription.url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        onPressed: () async {
                          final confirmed = await confirmActionDialog(
                            sheetContext,
                            title: '删除 IPTV 订阅',
                            message:
                                '确定删除“${subscription.name}”吗？相关频道缓存也会一并清理。',
                            confirmText: '删除',
                          );
                          if (!confirmed || !sheetContext.mounted) {
                            return;
                          }
                          repo.deleteSubscription(subscription.id);
                          ref.invalidate(iptvLibraryProvider);
                          Navigator.pop(sheetContext);
                        },
                        icon: const Icon(Icons.delete_outline_rounded),
                        tooltip: '删除',
                      ),
                    );
                  },
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemCount: library.subscriptions.length,
                ),
        ),
      ),
    );
  }

  Future<void> _showImportDialog(BuildContext context) async {
    final result = await showAppTextInputDialog(
      context,
      title: '导入 IPTV',
      hintText: '粘贴 m3u/m3u8/txt 订阅 URL，或包含 iptv 数组的 JSON',
      confirmText: '导入',
      minLines: 6,
      maxLines: 10,
      width: 560,
    );
    if (result == null || result.trim().isEmpty || !context.mounted) {
      return;
    }
    try {
      showBlockingProgressDialog(context, '正在导入直播源...');
      final repo = await ref.read(iptvRepositoryProvider.future);
      final value = result.trim();
      final importResult =
          value.startsWith('http://') || value.startsWith('https://')
          ? await repo.importSubscriptionUrl('IPTV 订阅', value)
          : await repo.importJson(value);
      if (!context.mounted) {
        return;
      }
      ref.invalidate(iptvLibraryProvider);
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            importResult.channels == 0 && importResult.errors.isEmpty
                ? 'IPTV 订阅无变化'
                : '导入 ${importResult.channels} 个频道，错误 ${importResult.errors.length} 个',
          ),
        ),
      );
    } catch (error) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }
}

class _LiveToolbar extends StatelessWidget {
  const _LiveToolbar({
    required this.groups,
    required this.group,
    required this.onGroupChanged,
    required this.onSearchChanged,
  });

  final List<String> groups;
  final String? group;
  final ValueChanged<String?> onGroupChanged;
  final ValueChanged<String> onSearchChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        children: [
          AppSearchField(hintText: '搜索频道', onChanged: onSearchChanged),
          const SizedBox(height: 12),
          LiveGroupSelector(
            groups: groups,
            group: group,
            onChanged: onGroupChanged,
          ),
        ],
      ),
    );
  }
}
