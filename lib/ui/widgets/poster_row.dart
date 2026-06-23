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
      height: itemWidth / (2 / 3),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemBuilder: (context, index) {
          final item = items[index];
          return SizedBox(
            width: itemWidth,
            child: PosterCard(
              item: item,
              metaMode: PosterMetaMode.compact,
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

class ContinueWatchRow extends StatelessWidget {
  const ContinueWatchRow({
    super.key,
    required this.records,
    required this.onTap,
    this.itemWidth = 118,
  });

  final List<WatchRecord> records;
  final ValueChanged<WatchRecord> onTap;
  final double itemWidth;

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      height: itemWidth / (2 / 3),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemBuilder: (context, index) {
          final record = records[index];
          return SizedBox(
            width: itemWidth,
            child: ContinueWatchCard(
              record: record,
              onTap: () => onTap(record),
            ),
          );
        },
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemCount: records.length,
      ),
    );
  }
}
