import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/app_providers.dart';
import '../ui/theme/app_system_ui.dart';
import '../ui/theme/app_theme.dart';
import 'router.dart';

class SkyTvApp extends ConsumerWidget {
  const SkyTvApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref
        .watch(themeModeProvider)
        .maybeWhen(data: (mode) => mode, orElse: () => ThemeMode.system);
    return MaterialApp.router(
      title: 'sky-tv',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      routerConfig: appRouter,
      builder: (context, child) =>
          AppSystemUi(child: child ?? const SizedBox()),
    );
  }
}
