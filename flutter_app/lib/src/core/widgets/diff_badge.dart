import 'package:flutter/material.dart';

import 'app_panel.dart';

/// A small badge showing a diff stat like "+3" or "-1" in a colored pill.
/// Used in the rewrite remote file dialogs.
class DiffBadge extends StatelessWidget {
  const DiffBadge({required this.label, required this.color, super.key});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .8)),
      ),
      child: Text(label, style: portixTitle(11).copyWith(color: color)),
    );
  }
}
