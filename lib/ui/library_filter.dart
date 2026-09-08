import 'package:flutter/material.dart';

import 'app_theme.dart';

class LibraryFilter extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color accent;
  final List<String> options;
  final ValueChanged<String> onSelected;

  const LibraryFilter({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
    required this.options,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: '$label: $value',
    initialValue: value,
    onSelected: onSelected,
    position: PopupMenuPosition.under,
    offset: const Offset(0, 8),
    color: panelColor,
    surfaceTintColor: Colors.transparent,
    elevation: 12,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: BorderSide(color: accent.withValues(alpha: 0.3)),
    ),
    itemBuilder: (context) => [
      for (final option in options)
        PopupMenuItem<String>(
          value: option,
          child: Row(children: [
            Icon(option == value ? Icons.check_circle_rounded : Icons.circle_outlined,
              size: 18, color: option == value ? accent : const Color(0xFF687A98)),
            const SizedBox(width: 12),
            Expanded(child: Text(option, style: TextStyle(
              color: option == value ? accent : null,
              fontWeight: option == value ? FontWeight.w700 : FontWeight.w400,
            ))),
          ]),
        ),
    ],
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [accent.withValues(alpha: 0.12), const Color(0xFF111A2C)]),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.32)),
      ),
      child: Row(children: [
        Icon(icon, color: accent, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label.toUpperCase(), style: TextStyle(
            color: accent, fontSize: 9, letterSpacing: 1.8, fontWeight: FontWeight.w700,
          )),
          const SizedBox(height: 4),
          Text(value == 'With unwatched episodes' ? 'Unwatched' : value,
            maxLines: 1, overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600)),
        ])),
        const SizedBox(width: 4),
        Icon(Icons.expand_more_rounded, color: accent, size: 18),
      ]),
    ),
  );
}
