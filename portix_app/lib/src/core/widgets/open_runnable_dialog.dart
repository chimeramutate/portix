import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_panel.dart';

/// Asks before handing a remote program to the OS, which would run it.
/// Anything but an explicit yes refuses.
Future<bool> confirmOpenRunnable(BuildContext context, String fileName) async {
  final open = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('Run this file?'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(fileName, style: portixTitle(14)),
            const SizedBox(height: 8),
            Text(
              'It comes from the server and your system may run it as a '
              'program on this computer. Open it only if you trust the file.',
              style: portixMuted(12),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialog, true),
          style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
          child: const Text('Open anyway'),
        ),
      ],
    ),
  );
  return open ?? false;
}
