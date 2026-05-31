import 'package:flutter/material.dart';

class AppPill extends StatelessWidget {
  const AppPill({
    required this.label,
    required this.color,
    super.key,
    this.background,
    this.icon = Icons.circle,
  });

  final String label;
  final Color color;
  final Color? background;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 180),
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: background ?? color.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: .7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 7, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
