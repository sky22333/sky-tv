import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/models/media_models.dart';
import '../features/category/category_page.dart';
import '../features/detail/detail_page.dart';
import '../features/home/home_page.dart';
import '../features/live/live_page.dart';
import '../features/player/live_player_page.dart';
import '../features/player/player_page.dart';
import '../features/search/search_page.dart';
import '../features/settings/settings_page.dart';
import '../features/sources/sources_page.dart';
import '../ui/theme/app_system_ui.dart';
import '../ui/widgets/app_logo.dart';
import 'shell.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    ShellRoute(
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        GoRoute(path: '/', builder: (context, state) => const HomePage()),
        GoRoute(
          path: '/search',
          builder: (context, state) => const SearchPage(),
        ),
        GoRoute(
          path: '/sources',
          builder: (context, state) => const SourcesPage(),
        ),
        GoRoute(path: '/live', builder: (context, state) => const LivePage()),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SettingsPage(),
        ),
      ],
    ),
    GoRoute(
      path: '/detail/:sourceId/:mediaId',
      builder: (context, state) => DetailPage(
        sourceId: state.pathParameters['sourceId']!,
        mediaId: state.pathParameters['mediaId']!,
      ),
    ),
    GoRoute(
      path: '/player/:sourceId/:mediaId',
      builder: (context, state) => PlayerPage(
        sourceId: state.pathParameters['sourceId']!,
        mediaId: state.pathParameters['mediaId']!,
        lineIndex: int.tryParse(state.uri.queryParameters['line'] ?? '') ?? 0,
        episodeIndex:
            int.tryParse(state.uri.queryParameters['episode'] ?? '') ?? 0,
        resume: state.uri.queryParameters['resume'] == '1',
        initialDetail: state.extra is MediaDetail
            ? state.extra! as MediaDetail
            : null,
      ),
    ),
    GoRoute(
      path: '/live/:channelId',
      builder: (context, state) =>
          LivePlayerPage(channelId: state.pathParameters['channelId']!),
    ),
    GoRoute(
      path: '/category/:sourceId/:categoryId',
      builder: (context, state) => CategoryPage(
        sourceId: state.pathParameters['sourceId']!,
        categoryId: state.pathParameters['categoryId']!,
      ),
    ),
  ],
  errorBuilder: (context, state) => SystemUiRestorer(
    child: Scaffold(
      appBar: AppBar(title: const AppBrandTitle()),
      body: SafeArea(
        top: false,
        child: Center(child: Text(state.error.toString())),
      ),
    ),
  ),
);
