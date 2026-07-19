import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_panel.dart';

/// A status placeholder widget for empty/loading/error states in file panes.
/// Used when no items are available or a connection issue occurred.
class PaneStatus extends StatelessWidget {
  const PaneStatus({
    required this.icon,
    required this.title,
    super.key,
    this.message,
    this.iconColor = AppColors.muted,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Color iconColor;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: iconColor, size: 32),
            const SizedBox(height: 12),
            Text(title, style: portixTitle(14)),
            if (message != null) ...[
              const SizedBox(height: 4),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: portixMuted(12),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 16),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
