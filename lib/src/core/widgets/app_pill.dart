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
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: background ?? color.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: color.withValues(alpha: .7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 6, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Inter',
                color: color,
                fontSize: 9,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
