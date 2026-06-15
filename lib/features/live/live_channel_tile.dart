import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/models/iptv_models.dart';

class LiveChannelTile extends StatelessWidget {
  const LiveChannelTile({
    super.key,
    required this.channel,
    required this.onTap,
    this.selected = false,
    this.dark = false,
  });

  final IptvChannel channel;
  final VoidCallback onTap;
  final bool selected;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = dark ? Colors.white : scheme.onSurface;
    final secondary = dark ? Colors.white70 : scheme.onSurfaceVariant;
    final background = dark
        ? (selected ? Colors.white24 : Colors.white10)
        : (selected ? scheme.primaryContainer : scheme.surfaceContainerHigh);
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              _ChannelLogo(url: channel.logo, dark: dark),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      channel.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      channel.group ?? '未分组',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: secondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.play_circle_fill_rounded,
                color: dark ? Colors.white : scheme.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChannelLogo extends StatelessWidget {
  const _ChannelLogo({required this.url, required this.dark});

  final String? url;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = ColoredBox(
      color: dark ? Colors.white12 : scheme.surfaceContainerHighest,
      child: Icon(
        Icons.live_tv_rounded,
        color: dark ? Colors.white70 : scheme.onSurfaceVariant,
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 48,
        height: 48,
        child: url == null || url!.isEmpty
            ? fallback
            : CachedNetworkImage(
                imageUrl: url!,
                fit: BoxFit.contain,
                placeholder: (_, _) => fallback,
                errorWidget: (_, _, _) => fallback,
              ),
      ),
    );
  }
}
