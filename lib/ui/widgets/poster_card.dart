import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/models/media_models.dart';
import 'poster_fallback.dart';

const densePosterGridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
  maxCrossAxisExtent: 124,
  childAspectRatio: 0.58,
  crossAxisSpacing: 8,
  mainAxisSpacing: 10,
);

enum PosterMetaMode { compact, withSource, hidden }

String? mediaMetaLine(
  MediaItem item, {
  required PosterMetaMode mode,
  bool omitCategory = false,
}) {
  return switch (mode) {
    PosterMetaMode.hidden => null,
    PosterMetaMode.compact => _joinMeta([
      item.year,
      if (!omitCategory) item.category,
    ]),
    PosterMetaMode.withSource => _joinMeta([
      item.year,
      if (!omitCategory) item.category,
      item.sourceName,
    ]),
  };
}

String? _joinMeta(List<String?> parts) {
  final text = parts
      .whereType<String>()
      .where((part) => part.isNotEmpty)
      .join(' · ');
  return text.isEmpty ? null : text;
}

int posterMemCacheFor(double displayWidth) {
  final ratio =
      WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
  return (displayWidth * ratio).ceil().clamp(88, 400);
}

class PosterImage extends StatelessWidget {
  const PosterImage({
    super.key,
    required this.url,
    required this.memCacheWidth,
    this.fit = BoxFit.cover,
  });

  final String? url;
  final int memCacheWidth;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    if (url == null || url!.isEmpty) {
      return const PosterFallback();
    }
    final cacheHeight = (memCacheWidth * 1.5).round();
    return CachedNetworkImage(
      imageUrl: url!,
      fit: fit,
      memCacheWidth: memCacheWidth,
      memCacheHeight: cacheHeight,
      placeholder: (_, _) => const PosterFallback(),
      errorWidget: (_, _, _) => const PosterFallback(),
    );
  }
}

class PosterCard extends StatelessWidget {
  const PosterCard({
    super.key,
    required this.item,
    required this.onTap,
    this.metaMode = PosterMetaMode.compact,
  });

  final MediaItem item;
  final VoidCallback onTap;
  final PosterMetaMode metaMode;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 160.0;
        final category = item.category?.trim();
        final showCategoryBadge = category != null && category.isNotEmpty;
        final meta = mediaMetaLine(
          item,
          mode: metaMode,
          omitCategory: showCategoryBadge,
        );
        return InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: 2 / 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  PosterImage(
                    url: item.poster,
                    memCacheWidth: posterMemCacheFor(width),
                  ),
                  if (showCategoryBadge)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: _PosterBadge(label: category),
                    ),
                  _PosterCaption(title: item.title, meta: meta),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class ContinueWatchCard extends StatelessWidget {
  const ContinueWatchCard({
    super.key,
    required this.record,
    required this.onTap,
  });

  final WatchRecord record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 118.0;
        final progress = record.durationMs <= 0
            ? 0.0
            : (record.positionMs / record.durationMs).clamp(0.0, 1.0);
        return InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: AspectRatio(
            aspectRatio: 2 / 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  PosterImage(
                    url: record.poster,
                    memCacheWidth: posterMemCacheFor(width),
                  ),
                  _PosterCaption(
                    title: record.title,
                    meta: '第 ${record.episodeIndex + 1} 集',
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: LinearProgressIndicator(
                      value: progress > 0 ? progress : null,
                      minHeight: 3,
                      backgroundColor: Colors.black38,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PosterBadge extends StatelessWidget {
  const _PosterBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            height: 1,
          ),
        ),
      ),
    );
  }
}

class _PosterCaption extends StatelessWidget {
  const _PosterCaption({required this.title, this.meta});

  final String title;
  final String? meta;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Colors.black.withValues(alpha: 0.82)],
          ),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(8, 20, 8, meta == null ? 8 : 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                ),
              ),
              if (meta != null) ...[
                const SizedBox(height: 3),
                Text(
                  meta!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 11,
                    height: 1.1,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
