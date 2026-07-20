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
    if (groups.length > 6) {
      final color = dark ? Colors.white : null;
      return DropdownButtonFormField<String?>(
        initialValue: group,
        isExpanded: true,
        borderRadius: BorderRadius.circular(AppInputDecoration.radius),
        style: color == null
            ? const TextStyle(fontSize: 14)
            : TextStyle(color: color, fontSize: 14),
        dropdownColor: dark ? Colors.black : null,
        decoration: AppInputDecoration.flat(
          context,
          prefixIcon: const Icon(Icons.format_list_bulleted_rounded, size: 20),
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
