import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../ui/widgets/state_views.dart';
import 'player_surface.dart';

const playerWideBreakpoint = 1000.0;

class PortraitPlayerScaffold extends StatelessWidget {
  const PortraitPlayerScaffold({
    super.key,
    this.wideAppBar,
    required this.bodyBuilder,
  });

  final PreferredSizeWidget? wideAppBar;
  final Widget Function(
    BuildContext context,
    BoxConstraints constraints,
    bool wide,
  )
  bodyBuilder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= playerWideBreakpoint;
        final scaffold = Scaffold(
          appBar: wide ? wideAppBar : null,
          backgroundColor: wide ? null : Colors.black,
          body: wide
              ? SafeArea(
                  top: false,
                  child: bodyBuilder(context, constraints, wide),
                )
              : bodyBuilder(context, constraints, wide),
        );
        if (wide) {
          return scaffold;
        }
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: playerPortraitSystemUi,
          child: scaffold,
        );
      },
    );
  }
}

/// 竖屏主流布局：黑色状态栏区 + 固定播放器 + 下方可滚动内容。
class PortraitPlayerLayout extends StatelessWidget {
  const PortraitPlayerLayout({
    super.key,
    required this.player,
    required this.content,
  });

  final Widget player;
  final Widget content;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final maxHeight = constraints.maxHeight;
        final topInset = MediaQuery.paddingOf(context).top;
        final idealPlayerHeight = width * 9 / 16;
        final playerHeight = idealPlayerHeight.clamp(
          0.0,
          (maxHeight - topInset).clamp(0.0, maxHeight),
        );

        return Column(
          children: [
            ColoredBox(
              color: Colors.black,
              child: SafeArea(
                bottom: false,
                child: SizedBox(
                  height: playerHeight,
                  width: width,
                  child: player,
                ),
              ),
            ),
            Expanded(
              child: ColoredBox(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: content,
              ),
            ),
          ],
        );
      },
    );
  }
}

class PlayerVideoBlock extends StatelessWidget {
  const PlayerVideoBlock({
    super.key,
    required this.controller,
    required this.title,
    required this.subtitle,
    required this.onEnterFullscreen,
    required this.onExitFullscreen,
    this.onBack,
    this.selectorAction,
    this.onNext,
    this.loading = false,
    this.loadError,
    this.maxPlayerHeight,
  });

  final VideoController controller;
  final String title;
  final ValueListenable<String> subtitle;
  final Future<void> Function() onEnterFullscreen;
  final Future<void> Function() onExitFullscreen;
  final VoidCallback? onBack;
  final PlayerSurfaceAction? selectorAction;
  final VoidCallback? onNext;
  final bool loading;
  final String? loadError;
  final double? maxPlayerHeight;

  @override
  Widget build(BuildContext context) {
    final video = AspectRatio(
      aspectRatio: 16 / 9,
      child: PlayerSurface(
        controller: controller,
        title: title,
        subtitle: subtitle,
        onBack: onBack,
        selectorAction: selectorAction,
        onNext: onNext,
        onEnterFullscreen: onEnterFullscreen,
        onExitFullscreen: onExitFullscreen,
      ),
    );
    Widget block = Stack(
      alignment: Alignment.bottomCenter,
      fit: StackFit.passthrough,
      children: [
        video,
        if (loading) const LinearProgressIndicator(minHeight: 2),
      ],
    );
    if (maxPlayerHeight != null) {
      block = Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxPlayerHeight!),
          child: block,
        ),
      );
    }
    if (loadError == null) {
      return block;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        block,
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: InlineState(
            icon: Icons.error_outline_rounded,
            title: '播放失败',
            message: loadError!,
          ),
        ),
      ],
    );
  }
}
