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
  const AppIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    Color? color,
    this.outlined = true,
    super.key,
  }) : _color = color;

  final IconData icon;

  /// False draws a plain icon (toolbars, tab strips) instead of a bordered box.
  final bool outlined;

  /// Shown on hover and read by screen readers; icon-only buttons need a name.
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? _color;
  Color get color => _color ?? AppColors.cyan;

  @override
  Widget build(BuildContext context) {
    if (!outlined) {
      return SizedBox.square(
        dimension: 28,
        child: IconButton(
          tooltip: tooltip,
          onPressed: onPressed,
          padding: EdgeInsets.zero,
          icon: Icon(icon, color: _color ?? AppColors.text, size: 17),
        ),
      );
    }
    return SizedBox(
      width: 30,
      height: 30,
      child: IconButton.outlined(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, color: color, size: 15),
        style:
            IconButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ).copyWith(
              side: focusRingSide(
                focus: AppColors.cyan,
                rest: BorderSide(color: AppColors.inputBorder),
              ),
            ),
      ),
    );
  }
}
