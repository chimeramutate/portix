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
