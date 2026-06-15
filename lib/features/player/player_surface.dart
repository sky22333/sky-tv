import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:volume_controller/volume_controller.dart';

Future<void> enterPlayerFullscreen() async {
  await Future.wait([
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
      overlays: [],
    ),
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]),
  ]);
}

class PlayerSurfaceAction {
  const PlayerSurfaceAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final void Function(BuildContext context) onPressed;
}

class PlayerSurface extends StatelessWidget {
  const PlayerSurface({
    super.key,
    required this.controller,
    required this.title,
    required this.subtitle,
    required this.onEnterFullscreen,
    required this.onExitFullscreen,
    this.selectorAction,
    this.onNext,
  });

  final VideoController controller;
  final String title;
  final ValueListenable<String> subtitle;
  final Future<void> Function() onEnterFullscreen;
  final Future<void> Function() onExitFullscreen;
  final PlayerSurfaceAction? selectorAction;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final player = controller.player;
    final desktop = _desktopControls(context);
    final mobileTheme = _mobileControlsTheme(
      title: title,
      subtitle: subtitle,
      selectorAction: selectorAction,
      onNext: onNext,
    );
    final desktopTheme = _desktopControlsTheme(
      context: context,
      player: player,
      title: title,
      subtitle: subtitle,
      selectorAction: selectorAction,
      onNext: onNext,
    );

    final child = ColoredBox(
      color: Colors.black,
      child: desktop
          ? MaterialDesktopVideoControlsTheme(
              normal: desktopTheme.normal,
              fullscreen: desktopTheme.fullscreen,
              child: Video(
                controller: controller,
                fit: BoxFit.contain,
                controls: MaterialDesktopVideoControls,
                onEnterFullscreen: onEnterFullscreen,
                onExitFullscreen: onExitFullscreen,
              ),
            )
          : MaterialVideoControlsTheme(
              normal: mobileTheme.normal,
              fullscreen: mobileTheme.fullscreen,
              child: Video(
                controller: controller,
                fit: BoxFit.contain,
                controls: MaterialVideoControls,
                onEnterFullscreen: onEnterFullscreen,
                onExitFullscreen: onExitFullscreen,
              ),
            ),
    );

    if (!desktop) {
      return child;
    }
    return ClipRRect(borderRadius: BorderRadius.circular(8), child: child);
  }

  bool _desktopControls(BuildContext context) {
    if (kIsWeb) {
      return false;
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux => true,
      _ => false,
    };
  }

  ({
    MaterialDesktopVideoControlsThemeData normal,
    MaterialDesktopVideoControlsThemeData fullscreen,
  })
  _desktopControlsTheme({
    required BuildContext context,
    required Player player,
    required String title,
    required ValueListenable<String> subtitle,
    required PlayerSurfaceAction? selectorAction,
    required VoidCallback? onNext,
  }) {
    final shortcuts = _desktopKeyboardShortcuts(context, player);
    final topBar = <Widget>[
      Expanded(
        child: _PlayerControlTitle(title: title, subtitle: subtitle),
      ),
    ];
    final bottomBar = <Widget>[
      const MaterialDesktopPlayOrPauseButton(),
      const SizedBox(width: 8),
      const MaterialDesktopVolumeButton(),
      const SizedBox(width: 8),
      const MaterialDesktopPositionIndicator(),
      const Spacer(),
      if (onNext != null)
        MaterialDesktopCustomButton(
          icon: const Icon(Icons.skip_next_rounded),
          onPressed: onNext,
        ),
      if (selectorAction != null)
        MaterialDesktopCustomButton(
          icon: Icon(selectorAction.icon),
          onPressed: () => selectorAction.onPressed(context),
        ),
      const MaterialDesktopFullscreenButton(),
    ];

    return (
      normal: kDefaultMaterialDesktopVideoControlsThemeData.copyWith(
        keyboardShortcuts: shortcuts,
        visibleOnMount: true,
        playAndPauseOnTap: true,
        displaySeekBar: true,
        topButtonBar: topBar,
        topButtonBarMargin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        bottomButtonBar: bottomBar,
        bottomButtonBarMargin: const EdgeInsets.symmetric(horizontal: 12),
        seekBarMargin: const EdgeInsets.symmetric(horizontal: 16),
        seekBarPositionColor: Colors.white,
        seekBarThumbColor: Colors.white,
        seekBarHeight: 2.4,
        seekBarHoverHeight: 4.8,
      ),
      fullscreen: kDefaultMaterialDesktopVideoControlsThemeDataFullscreen
          .copyWith(
            keyboardShortcuts: shortcuts,
            playAndPauseOnTap: true,
            displaySeekBar: true,
            topButtonBar: topBar,
            topButtonBarMargin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            bottomButtonBar: bottomBar,
            bottomButtonBarMargin: const EdgeInsets.fromLTRB(12, 0, 12, 16),
            seekBarMargin: const EdgeInsets.symmetric(horizontal: 16),
            seekBarPositionColor: Colors.white,
            seekBarThumbColor: Colors.white,
          ),
    );
  }

  Map<ShortcutActivator, VoidCallback> _desktopKeyboardShortcuts(
    BuildContext context,
    Player player,
  ) {
    return {
      const SingleActivator(LogicalKeyboardKey.space): () =>
          unawaited(player.playOrPause()),
      const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
        final position = player.state.position - const Duration(seconds: 5);
        unawaited(player.seek(position));
      },
      const SingleActivator(LogicalKeyboardKey.arrowRight): () {
        final position = player.state.position + const Duration(seconds: 5);
        unawaited(player.seek(position));
      },
      const SingleActivator(LogicalKeyboardKey.arrowUp): () {
        final volume = (player.state.volume + 5).clamp(0.0, 100.0);
        unawaited(player.setVolume(volume));
      },
      const SingleActivator(LogicalKeyboardKey.arrowDown): () {
        final volume = (player.state.volume - 5).clamp(0.0, 100.0);
        unawaited(player.setVolume(volume));
      },
      const SingleActivator(LogicalKeyboardKey.keyM): () {
        final volume = player.state.volume == 0 ? 100.0 : 0.0;
        unawaited(player.setVolume(volume));
      },
    };
  }

  ({
    MaterialVideoControlsThemeData normal,
    MaterialVideoControlsThemeData fullscreen,
  })
  _mobileControlsTheme({
    required String title,
    required ValueListenable<String> subtitle,
    required PlayerSurfaceAction? selectorAction,
    required VoidCallback? onNext,
  }) {
    final gestures = _PlayerGestureControls();
    final topBar = <Widget>[
      const _FullscreenBackButton(),
      Expanded(
        child: _PlayerControlTitle(title: title, subtitle: subtitle),
      ),
    ];

    return (
      normal: kDefaultMaterialVideoControlsThemeData.copyWith(
        volumeGesture: true,
        brightnessGesture: true,
        seekOnDoubleTap: true,
        seekGesture: true,
        visibleOnMount: true,
        onVolumeChanged: gestures.setVolume,
        onBrightnessChanged: gestures.setBrightness,
        onBrightnessReset: gestures.resetBrightness,
        displaySeekBar: false,
        topButtonBar: const [],
        bottomButtonBar: [
          const _PlayerTimeLabel(position: true),
          const SizedBox(width: 10),
          const Expanded(child: MaterialSeekBar()),
          const SizedBox(width: 10),
          const _PlayerTimeLabel(position: false),
          const SizedBox(width: 4),
          if (onNext != null) _PlayerNextButton(onPressed: onNext),
          const MaterialFullscreenButton(),
        ],
        bottomButtonBarMargin: const EdgeInsets.fromLTRB(16, 0, 8, 8),
        seekBarMargin: EdgeInsets.zero,
        seekBarContainerHeight: 24,
        seekBarHeight: 2.2,
        seekBarAlignment: Alignment.center,
        seekBarPositionColor: Colors.white,
        seekBarThumbColor: Colors.white,
      ),
      fullscreen: kDefaultMaterialVideoControlsThemeDataFullscreen.copyWith(
        volumeGesture: true,
        brightnessGesture: true,
        seekOnDoubleTap: true,
        seekGesture: true,
        speedUpOnLongPress: true,
        onVolumeChanged: gestures.setVolume,
        onBrightnessChanged: gestures.setBrightness,
        onBrightnessReset: gestures.resetBrightness,
        displaySeekBar: false,
        topButtonBar: topBar,
        topButtonBarMargin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        bottomButtonBar: [
          const _PlayerTimeLabel(position: true),
          const SizedBox(width: 10),
          const Expanded(child: MaterialSeekBar()),
          const SizedBox(width: 10),
          const _PlayerTimeLabel(position: false),
          const SizedBox(width: 6),
          if (onNext != null) ...[
            _PlayerNextButton(onPressed: onNext),
            const SizedBox(width: 6),
          ],
          if (selectorAction != null) ...[
            _PlayerSelectorButton(action: selectorAction),
            const SizedBox(width: 6),
          ],
          const MaterialFullscreenButton(),
        ],
        bottomButtonBarMargin: const EdgeInsets.fromLTRB(16, 0, 8, 24),
        seekBarMargin: EdgeInsets.zero,
        seekBarContainerHeight: 24,
        seekBarAlignment: Alignment.center,
        seekBarPositionColor: Colors.white,
        seekBarThumbColor: Colors.white,
      ),
    );
  }
}

class _PlayerGestureControls {
  void setVolume(double value) {
    VolumeController.instance.showSystemUI = false;
    unawaited(VolumeController.instance.setVolume(value).catchError((_) {}));
  }

  void setBrightness(double value) {
    unawaited(
      ScreenBrightness.instance
          .setApplicationScreenBrightness(value)
          .catchError((_) {}),
    );
  }

  void resetBrightness() {
    unawaited(
      ScreenBrightness.instance.resetApplicationScreenBrightness().catchError(
        (_) {},
      ),
    );
  }
}

class _PlayerNextButton extends StatelessWidget {
  const _PlayerNextButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return MaterialCustomButton(
      icon: const Icon(Icons.skip_next_rounded),
      onPressed: onPressed,
    );
  }
}

class _PlayerSelectorButton extends StatelessWidget {
  const _PlayerSelectorButton({required this.action});

  final PlayerSurfaceAction action;

  @override
  Widget build(BuildContext context) {
    return MaterialCustomButton(
      icon: Icon(action.icon),
      onPressed: () => action.onPressed(context),
    );
  }
}

class _PlayerTimeLabel extends StatelessWidget {
  const _PlayerTimeLabel({required this.position});

  final bool position;

  @override
  Widget build(BuildContext context) {
    final player = VideoStateInheritedWidget.of(
      context,
    ).state.widget.controller.player;
    final stream = position ? player.stream.position : player.stream.duration;
    final initial = position ? player.state.position : player.state.duration;
    return SizedBox(
      width: 58,
      child: StreamBuilder<Duration>(
        stream: stream,
        initialData: initial,
        builder: (context, snapshot) => Text(
          _formatDuration(snapshot.data ?? Duration.zero),
          maxLines: 1,
          textAlign: position ? TextAlign.left : TextAlign.right,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            height: 1,
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final total = duration.inSeconds;
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    final seconds = total % 60;
    final secondText = seconds.toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:$secondText';
    }
    return '$minutes:$secondText';
  }
}

class _FullscreenBackButton extends StatelessWidget {
  const _FullscreenBackButton();

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () => exitFullscreen(context),
      icon: const Icon(Icons.arrow_back_rounded),
      color: Colors.white,
      tooltip: '退出全屏',
    );
  }
}

class _PlayerControlTitle extends StatelessWidget {
  const _PlayerControlTitle({required this.title, required this.subtitle});

  final String title;
  final ValueListenable<String> subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        ValueListenableBuilder<String>(
          valueListenable: subtitle,
          builder: (context, value, _) => Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ),
      ],
    );
  }
}
