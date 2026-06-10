import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'app_panel.dart';

/// Reusable path input bar with a folder icon and submit button.
/// Used in both the SSH remote folder panel and the SFTP file pane.
class PathCrumb extends StatelessWidget {
  const PathCrumb({
    required this.path,
    required this.onSubmit,
    super.key,
    this.icon = Icons.folder_outlined,
    this.iconColor = AppColors.muted,
  });

  final String path;
  final ValueChanged<String> onSubmit;
  final IconData icon;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    final controller = TextEditingController(text: path);
    return AppPanel(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 2),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 16),
          const SizedBox(width: 9),
          Expanded(
            child: TextField(
              controller: controller,
              onSubmitted: onSubmit,
              style: const TextStyle(
                color: AppColors.text,
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Open path',
            onPressed: () => onSubmit(controller.text),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 30, height: 30),
            icon: const Icon(
              Icons.keyboard_return_rounded,
              color: AppColors.muted,
              size: 17,
            ),
          ),
        ],
      ),
    );
  }
}
