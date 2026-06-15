import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../ui/theme/app_system_ui.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  static const _items = [
    _NavItem('首页', Icons.home_rounded, '/'),
    _NavItem('搜索', Icons.search_rounded, '/search'),
    _NavItem('直播', Icons.live_tv_rounded, '/live'),
    _NavItem('影视', Icons.movie_filter_rounded, '/sources'),
    _NavItem('设置', Icons.settings_rounded, '/settings'),
  ];

  @override
  Widget build(BuildContext context) {
    final current = _currentIndex(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 700) {
          return SystemUiRestorer(
            child: Scaffold(
              body: SafeArea(
                child: Row(
                  children: [
                    NavigationRail(
                      selectedIndex: current,
                      onDestinationSelected: (index) =>
                          context.go(_items[index].path),
                      labelType: NavigationRailLabelType.all,
                      destinations: [
                        for (final item in _items)
                          NavigationRailDestination(
                            icon: Icon(item.icon),
                            label: Text(item.label),
                          ),
                      ],
                    ),
                    const VerticalDivider(width: 1),
                    Expanded(child: child),
                  ],
                ),
              ),
            ),
          );
        }
        final background = Theme.of(context).scaffoldBackgroundColor;
        final scheme = Theme.of(context).colorScheme;
        final navigationColor = Color.alphaBlend(
          scheme.primary.withValues(alpha: 0.04),
          background,
        );
        return SystemUiRestorer(
          child: Scaffold(
            backgroundColor: background,
            body: child,
            bottomNavigationBar: ColoredBox(
              color: navigationColor,
              child: SafeArea(
                top: false,
                child: NavigationBar(
                  backgroundColor: navigationColor,
                  indicatorColor: scheme.primaryContainer.withValues(
                    alpha: 0.72,
                  ),
                  surfaceTintColor: Colors.transparent,
                  selectedIndex: current,
                  onDestinationSelected: (index) =>
                      context.go(_items[index].path),
                  destinations: [
                    for (final item in _items)
                      NavigationDestination(
                        icon: Icon(item.icon),
                        label: item.label,
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  int _currentIndex(BuildContext context) {
    final path = GoRouterState.of(context).uri.path;
    final index = _items.indexWhere((item) => item.path == path);
    return index < 0 ? 0 : index;
  }
}

class _NavItem {
  const _NavItem(this.label, this.icon, this.path);
  final String label;
  final IconData icon;
  final String path;
}
