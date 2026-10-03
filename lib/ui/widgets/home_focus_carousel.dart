import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/models/media_models.dart';
import 'poster_card.dart';

/// 首页竖版焦点轮播：环形无限滚动，无 3D，复用 [PosterCard]。
class HomeFocusCarousel extends StatelessWidget {
  const HomeFocusCarousel({
    super.key,
    required this.items,
    required this.onTap,
  });

  final List<MediaItem> items;
  final ValueChanged<MediaItem> onTap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final slotWidth = (constraints.maxWidth * 0.38).clamp(10.0, 230.0);
        return _HomeFocusViewport(
          items: items,
          onTap: onTap,
          viewportFraction: slotWidth / constraints.maxWidth,
          height: (slotWidth - 10) / (2 / 3),
        );
      },
    );
  }
}

class _HomeFocusViewport extends StatefulWidget {
  const _HomeFocusViewport({
    required this.items,
    required this.onTap,
    required this.viewportFraction,
    required this.height,
  });

  final List<MediaItem> items;
  final ValueChanged<MediaItem> onTap;
  final double viewportFraction;
  final double height;

  @override
  State<_HomeFocusViewport> createState() => _HomeFocusCarouselState();
}

class _HomeFocusCarouselState extends State<_HomeFocusViewport>
    with WidgetsBindingObserver {
  static const _interval = Duration(seconds: 5);

  /// 有限环 + 近边缘 jump 回中段，避免 n×1000 虚页。
  static const _loops = 40;

  late PageController _controller;
  Timer? _timer;
  var _page = 0;
  var _dragging = false;
  var _active = true;
  var _jumping = false;

  int get _n => widget.items.length;
  bool get _loop => _n >= 2;
  int get _count => _loop ? _n * _loops : _n;
  int _start() => _loop ? _n * (_loops ~/ 2) : 0;
  int _real(int page) => page % _n;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _page = _start();
    _controller = PageController(
      viewportFraction: widget.viewportFraction,
      initialPage: _page,
      keepPage: false,
    );
    _arm();
  }

  @override
  void didUpdateWidget(covariant _HomeFocusViewport oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length != widget.items.length ||
        oldWidget.viewportFraction != widget.viewportFraction) {
      if (oldWidget.items.length != widget.items.length) {
        _page = _start();
      }
      _controller.dispose();
      _controller = PageController(
        viewportFraction: widget.viewportFraction,
        initialPage: _page,
        keepPage: false,
      );
      _arm();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    _arm();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _arm() {
    _timer?.cancel();
    _timer = null;
    if (!_active || _dragging || !mounted || !_loop) {
      return;
    }
    _timer = Timer.periodic(_interval, (_) {
      if (!mounted || !_controller.hasClients || !_loop || _jumping) {
        return;
      }
      _controller.animateToPage(
        _page + 1,
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _onPageChanged(int index) {
    if (_jumping) {
      return;
    }
    setState(() => _page = index);
    if (!_loop || !_controller.hasClients) {
      return;
    }
    final margin = _n * 2;
    if (index < margin || index >= _count - margin) {
      final target = _start() + _real(index);
      _jumping = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_controller.hasClients) {
          _jumping = false;
          return;
        }
        _controller.jumpToPage(target);
        setState(() {
          _page = target;
          _jumping = false;
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;

    return Column(
      children: [
        SizedBox(
          height: widget.height,
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n is ScrollStartNotification && n.dragDetails != null) {
                _dragging = true;
                _arm();
              } else if (n is ScrollEndNotification) {
                _dragging = false;
                _arm();
              }
              return false;
            },
            child: PageView.builder(
              controller: _controller,
              itemCount: _count,
              onPageChanged: _onPageChanged,
              itemBuilder: (context, i) {
                final item = items[_real(i)];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: PosterCard(
                    item: item,
                    onTap: () => widget.onTap(item),
                  ),
                );
              },
            ),
          ),
        ),
        if (_loop) ...[
          const SizedBox(height: 10),
          _Dots(count: _n, index: _real(_page)),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final on = i == index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: on ? 14 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: on
                ? scheme.primary
                : scheme.onSurface.withValues(alpha: 0.22),
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }
}
