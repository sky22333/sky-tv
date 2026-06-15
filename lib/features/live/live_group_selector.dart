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
        style: color == null ? null : TextStyle(color: color),
        dropdownColor: dark ? Colors.black : null,
        decoration: AppInputDecoration.flat(
          context,
          prefixIcon: const Icon(Icons.format_list_bulleted_rounded, size: 22),
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
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, index) {
          final value = index == 0 ? null : groups[index - 1];
          return ChoiceChip(
            label: Text(value ?? '全部'),
            selected: value == group,
            showCheckmark: false,
            onSelected: (_) => onChanged(value),
          );
        },
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemCount: groups.length + 1,
      ),
    );
  }
}
