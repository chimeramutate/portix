import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

const sidePanelWidth = 240.0;

/// The column between the workspace rail and the content: a small caps
/// title, an optional header [action], then [child] filling the rest.
class SidePanel extends StatelessWidget {
  const SidePanel({
    required this.title,
    required this.child,
    this.action,
    super.key,
  });

  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: sidePanelWidth,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 36,
            child: Padding(
              padding: const EdgeInsets.only(left: 16, right: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title.toUpperCase(),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        letterSpacing: .8,
                      ),
                    ),
                  ),
                  ?action,
                ],
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// One row of a [SidePanel] list: icon, label, optional [subtitle] line and
/// [count] badge. The selected row gets the selection fill and an accent
/// marker on its left edge.
class SidePanelTile extends StatelessWidget {
  const SidePanelTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.count,
    super.key,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget? subtitle;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final count = this.count;
    final title = Text(
      label,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: selected ? AppColors.text : AppColors.muted,
        fontWeight: FontWeight.w500,
        fontSize: 13,
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? AppColors.selected : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          hoverColor: AppColors.surfaceDark,
          child: Container(
            height: subtitle == null ? 32 : 44,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: selected ? AppColors.accent : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: selected ? AppColors.accent : AppColors.muted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: subtitle == null
                      ? title
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [title, subtitle!],
                        ),
                ),
                if (count != null)
                  Container(
                    constraints: const BoxConstraints(minWidth: 22),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.accent.withValues(alpha: .15)
                          : AppColors.surfaceDark,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      '$count',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: selected ? AppColors.accent : AppColors.muted,
                        fontWeight: FontWeight.w400,
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
