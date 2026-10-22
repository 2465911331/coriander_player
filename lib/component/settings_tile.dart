import 'package:flutter/material.dart';

class SettingsTile extends StatelessWidget {
  const SettingsTile(
      {super.key, required this.description, required this.action});
  final String description;
  final Widget action;
  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, bounds) {
        final label =
            Text(description, style: Theme.of(context).textTheme.titleMedium);
        if (bounds.maxWidth < 600 ||
            MediaQuery.textScalerOf(context).scale(16) > 22) {
          return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                label,
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerLeft, child: action)
              ]);
        }
        return Row(children: [
          Expanded(child: label),
          const SizedBox(width: 16),
          action
        ]);
      });
}
