import 'package:flutter/material.dart';

import '../../core/models/media_models.dart';
import 'poster_card.dart';

class PosterRow extends StatelessWidget {
  const PosterRow({
    super.key,
    required this.items,
    required this.onTap,
    this.itemWidth = 118,
  });

  final List<MediaItem> items;
  final ValueChanged<MediaItem> onTap;
  final double itemWidth;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      height: itemWidth / (2 / 3) + 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemBuilder: (context, index) {
          final item = items[index];
          return SizedBox(
            width: itemWidth,
            child: PosterCard(
              item: item,
              showSourceName: false,
              onTap: () => onTap(item),
            ),
          );
        },
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemCount: items.length,
      ),
    );
  }
}
