import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class AppButton extends StatelessWidget {
  const AppButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    super.key,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 30,
      child: primary
          ? FilledButton.icon(
              onPressed: onPressed,
              icon: Icon(icon, size: 14),
              label: Text(label, overflow: TextOverflow.ellipsis),
            )
          : OutlinedButton.icon(
              onPressed: onPressed,
              icon: Icon(icon, size: 14),
              label: Text(label, overflow: TextOverflow.ellipsis),
              style: OutlinedButton.styleFrom(
                backgroundColor: AppColors.surfaceCard.withValues(alpha: .55),
              ),
            ),
    );
  }
}

class AppIconButton extends StatelessWidget {
  const AppIconButton({required this.icon, required this.onPressed, super.key});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 30,
      height: 30,
      child: IconButton.outlined(
        onPressed: onPressed,
        icon: Icon(icon, color: AppColors.cyan, size: 15),
        style: IconButton.styleFrom(
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}
