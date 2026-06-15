import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/repositories/app_providers.dart';
import '../../ui/widgets/app_dialogs.dart';
import '../../ui/widgets/app_logo.dart';
import '../../ui/widgets/state_views.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  static final Uri _projectUri = Uri.parse(
    'https://github.com/sky22333/sky-tv',
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final userAgent = ref.watch(customUserAgentProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: [
          const SectionHeader(title: '外观'),
          themeMode.when(
            data: (mode) => _ThemeModeGroup(value: mode),
            error: (error, _) => ListTile(
              leading: const Icon(Icons.error_outline_rounded),
              title: const Text('主题设置读取失败'),
              subtitle: Text(error.toString()),
            ),
            loading: () => const ListTile(
              leading: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              title: Text('正在读取主题设置'),
            ),
          ),
          const SectionHeader(title: '网络'),
          userAgent.when(
            data: (value) => ListTile(
              leading: const Icon(Icons.travel_explore_rounded),
              title: const Text('自定义 UA'),
              subtitle: Text(value.isEmpty ? '未设置，使用系统默认请求头' : value),
              onTap: () => _editUserAgent(context, ref, value),
            ),
            error: (error, _) => ListTile(
              leading: const Icon(Icons.error_outline_rounded),
              title: const Text('UA 设置读取失败'),
              subtitle: Text(error.toString()),
            ),
            loading: () => const ListTile(
              leading: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              title: Text('正在读取 UA 设置'),
            ),
          ),
          const SectionHeader(title: '数据'),
          ListTile(
            leading: const Icon(Icons.refresh_rounded),
            title: const Text('刷新首页数据'),
            subtitle: const Text('刷新推荐、续看与收藏'),
            onTap: () {
              ref.invalidate(homeDataProvider);
              ref.invalidate(homeRecommendProvider);
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('首页数据已刷新')));
            },
          ),
          ListTile(
            leading: const Icon(Icons.cleaning_services_rounded),
            title: const Text('清理缓存'),
            subtitle: const Text('清理推荐、分类与海报缓存'),
            onTap: () => _confirmClearCache(context, ref),
          ),
          const SectionHeader(title: '关于'),
          ListTile(
            leading: const AppLogo(size: 36),
            title: const Text('sky-tv'),
            subtitle: const Text('跨平台视频播放器'),
            onTap: () => _openProject(context),
          ),
        ],
      ),
    );
  }

  Future<void> _openProject(BuildContext context) async {
    final opened = await launchUrl(
      _projectUri,
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('无法打开项目地址')));
    }
  }

  Future<void> _editUserAgent(
    BuildContext context,
    WidgetRef ref,
    String value,
  ) async {
    final result = await showAppTextInputDialog(
      context,
      title: '自定义 UA',
      hintText: '留空表示使用系统默认请求头',
      confirmText: '保存',
      initialValue: value,
      minLines: 1,
      maxLines: 3,
      autofocus: true,
    );
    if (result == null || !context.mounted) {
      return;
    }
    final repo = await ref.read(settingsRepositoryProvider.future);
    await repo.setCustomUserAgent(result);
    ref.invalidate(customUserAgentProvider);
    ref.invalidate(requestHeadersProvider);
    ref.invalidate(macCmsApiProvider);
    ref.invalidate(mediaRepositoryProvider);
    ref.invalidate(sourceRepositoryProvider);
    ref.invalidate(iptvRepositoryProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('UA 设置已保存')));
    }
  }

  Future<void> _confirmClearCache(BuildContext context, WidgetRef ref) async {
    final confirmed = await confirmActionDialog(
      context,
      title: '清理缓存',
      message: '将清理推荐、分类、直播等缓存与海报图片，不会删除订阅、收藏和观看记录。',
      confirmText: '清理',
    );
    if (!confirmed || !context.mounted) {
      return;
    }
    try {
      final db = await ref.read(databaseProvider.future);
      db.clearCache();
      ref.invalidate(homeDataProvider);
      ref.invalidate(homeRecommendProvider);
      ref.invalidate(sourcesProvider);
      ref.invalidate(sourceRepositoryProvider);
      ref.invalidate(iptvRepositoryProvider);
      ref.invalidate(iptvLibraryProvider);
      ref.invalidate(mediaRepositoryProvider);
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('缓存已清理')));
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('清理失败：$error')));
    }
  }
}

class _ThemeModeGroup extends ConsumerWidget {
  const _ThemeModeGroup({required this.value});

  final ThemeMode value;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: SegmentedButton<ThemeMode>(
        segments: const [
          ButtonSegment(
            value: ThemeMode.system,
            icon: Icon(Icons.brightness_auto_rounded),
            label: Text('系统'),
          ),
          ButtonSegment(
            value: ThemeMode.light,
            icon: Icon(Icons.light_mode_rounded),
            label: Text('浅色'),
          ),
          ButtonSegment(
            value: ThemeMode.dark,
            icon: Icon(Icons.dark_mode_rounded),
            label: Text('深色'),
          ),
        ],
        selected: {value},
        onSelectionChanged: (selected) {
          _setThemeMode(ref, selected.first);
        },
        showSelectedIcon: false,
        style: const ButtonStyle(
          visualDensity: VisualDensity(horizontal: -1, vertical: -1),
        ),
      ),
    );
  }

  Future<void> _setThemeMode(WidgetRef ref, ThemeMode mode) async {
    if (mode == value) {
      return;
    }
    final repo = await ref.read(settingsRepositoryProvider.future);
    await repo.setThemeMode(mode);
    ref.invalidate(themeModeProvider);
  }
}
