import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppSystemUi extends StatelessWidget {
  const AppSystemUi({super.key, required this.child});

  final Widget child;

  static Future<void> restore() {
    return Future.wait([
      SystemChrome.setPreferredOrientations(DeviceOrientation.values),
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final background = Theme.of(context).scaffoldBackgroundColor;
    final brightness = Theme.of(context).brightness;
    final dark = brightness == Brightness.dark;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: background,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: background,
        systemNavigationBarDividerColor: background,
        systemNavigationBarContrastEnforced: false,
        systemStatusBarContrastEnforced: false,
        systemNavigationBarIconBrightness: dark
            ? Brightness.light
            : Brightness.dark,
      ),
      child: ColoredBox(color: background, child: child),
    );
  }
}

class SystemUiRestorer extends StatefulWidget {
  const SystemUiRestorer({super.key, required this.child});

  final Widget child;

  @override
  State<SystemUiRestorer> createState() => _SystemUiRestorerState();
}

class _SystemUiRestorerState extends State<SystemUiRestorer> {
  @override
  void initState() {
    super.initState();
    _restoreAfterFrame();
  }

  @override
  void didUpdateWidget(covariant SystemUiRestorer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _restoreAfterFrame();
  }

  void _restoreAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(AppSystemUi.restore());
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
