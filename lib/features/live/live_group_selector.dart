import 'package:flutter/material.dart';

import '../../ui/widgets/app_search_field.dart';

class LiveGroupSelector extends StatelessWidget {
  const LiveGroupSelector({
    super.key,
    required this.groups,
    required this.group,
    required this.onChanged,
    this.dark = false,
  });

  final List<String> groups;
  final String? group;
  final ValueChanged<String?> onChanged;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 播放器深色浮层用不依赖 ColorScheme 的对比色；普通页跟主题 onSurface。
    final foreground = dark ? Colors.white : scheme.onSurface;
    final muted = dark ? Colors.white70 : scheme.onSurfaceVariant;

    if (groups.length > 6) {
      return DropdownButtonFormField<String?>(
        initialValue: group,
        isExpanded: true,
        borderRadius: BorderRadius.circular(AppInputDecoration.radius),
        style: TextStyle(color: foreground, fontSize: 14),
        iconEnabledColor: muted,
        iconDisabledColor: muted.withValues(alpha: 0.4),
        dropdownColor: dark ? Colors.black : scheme.surfaceContainerHigh,
        decoration: AppInputDecoration.flat(
          context,
          prefixIcon: Icon(
            Icons.format_list_bulleted_rounded,
            size: 20,
            color: muted,
          ),
          dark: dark,
        ),
        items: [
          const DropdownMenuItem<String?>(value: null, child: Text('全部')),
          for (final item in groups)
            DropdownMenuItem<String?>(
              value: item,
              child: Text(item, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: onChanged,
      );
    }

    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, index) {
          final value = index == 0 ? null : groups[index - 1];
          return ChoiceChip(
            label: Text(value ?? '全部', style: const TextStyle(fontSize: 13)),
            selected: value == group,
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            labelPadding: const EdgeInsets.symmetric(horizontal: 4),
            onSelected: (_) => onChanged(value),
          );
        },
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemCount: groups.length + 1,
      ),
    );
  }
}
