import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/models/media_models.dart';
import 'poster_fallback.dart';

const posterGridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
  maxCrossAxisExtent: 170,
  childAspectRatio: 0.48,
  crossAxisSpacing: 14,
  mainAxisSpacing: 18,
);

const densePosterGridDelegate = SliverGridDelegateWithMaxCrossAxisExtent(
  maxCrossAxisExtent: 124,
  childAspectRatio: 0.42,
  crossAxisSpacing: 8,
  mainAxisSpacing: 10,
);

const posterMemCacheWidth = 400;
const posterMemCacheHeight = 600;

class PosterCard extends StatelessWidget {
  const PosterCard({
    super.key,
    required this.item,
    required this.onTap,
    this.showSourceName = true,
  });

  final MediaItem item;
  final VoidCallback onTap;
  final bool showSourceName;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 2 / 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: item.poster == null
                  ? const PosterFallback()
                  : CachedNetworkImage(
                      imageUrl: item.poster!,
                      fit: BoxFit.cover,
                      memCacheWidth: posterMemCacheWidth,
                      memCacheHeight: posterMemCacheHeight,
                      placeholder: (_, _) => const PosterFallback(),
                      errorWidget: (_, _, _) => const PosterFallback(),
                    ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, height: 1.15),
          ),
          if (showSourceName) ...[
            const SizedBox(height: 3),
            Text(
              item.sourceName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
