import 'package:flutter/material.dart';

const episodeGridSpacing = 10.0;
const episodeGridMinTileWidth = 108.0;
const episodeGridTileHeight = 38.0;

int episodeGridColumnsFor(double width) {
  return (width / episodeGridMinTileWidth).floor().clamp(3, 6);
}

/// 虚拟化分集网格（必须作为 CustomScrollView / 可滚动视口的 sliver）。
class EpisodeGridSliver extends StatelessWidget {
  const EpisodeGridSliver({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.padding = EdgeInsets.zero,
  });

  final int itemCount;
  final NullableIndexedWidgetBuilder itemBuilder;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    if (itemCount <= 0) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    return SliverPadding(
      padding: padding,
      sliver: SliverLayoutBuilder(
        builder: (context, constraints) {
          final columns = episodeGridColumnsFor(constraints.crossAxisExtent);
          return SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisExtent: episodeGridTileHeight,
              crossAxisSpacing: episodeGridSpacing,
              mainAxisSpacing: episodeGridSpacing,
            ),
            delegate: SliverChildBuilderDelegate(
              itemBuilder,
              childCount: itemCount,
              addAutomaticKeepAlives: false,
            ),
          );
        },
      ),
    );
  }
}

enum EpisodeChipStyle { surface, overlay }

class EpisodeChip extends StatelessWidget {
  const EpisodeChip({
    super.key,
    required this.title,
    required this.selected,
    required this.onPressed,
    this.style = EpisodeChipStyle.surface,
  });

  final String title;
  final bool selected;
  final VoidCallback onPressed;
  final EpisodeChipStyle style;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Color background;
    final Color textColor;
    final BoxBorder? border;

    if (style == EpisodeChipStyle.overlay) {
      background = selected
          ? scheme.primary.withValues(alpha: 0.12)
          : Colors.white.withValues(alpha: 0.04);
      textColor = selected ? Colors.white : Colors.white70;
      border = Border.all(
        color: selected
            ? scheme.primary.withValues(alpha: 0.85)
            : Colors.white.withValues(alpha: 0.18),
        width: selected ? 1.5 : 1,
      );
    } else {
      background = selected
          ? scheme.primaryContainer
          : scheme.surfaceContainerHighest;
      textColor = selected
          ? scheme.onPrimaryContainer
          : scheme.onSurfaceVariant;
      border = null;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Ink(
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(8),
            border: border,
          ),
          child: Center(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: textColor,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
