import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class AppPanel extends StatelessWidget {
  const AppPanel({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
    this.color = AppColors.surface,
    this.borderColor = AppColors.border,
    this.radius = 8,
    /// Set to false when used inside unconstrained parents (e.g. overlay
    /// dropdowns, optionsViewBuilder) to avoid "infinite width" layout errors.
    this.fillWidth = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color color;
  final Color borderColor;
  final double radius;
  final bool fillWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: fillWidth ? double.infinity : null,
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: borderColor),
      ),
      child: child,
    );
  }
}

TextStyle portixTitle([double size = 14]) {
  return TextStyle(
    fontFamily: 'Inter',
    color: AppColors.text,
    fontSize: size,
    fontWeight: FontWeight.w900,
  );
}

TextStyle portixMuted([double size = 12]) {
  return TextStyle(
    fontFamily: 'Inter',
    color: AppColors.muted,
    fontSize: size,
    fontWeight: FontWeight.w600,
  );
}

TextStyle portixLabel([double size = 12]) {
  return TextStyle(
    fontFamily: 'Inter',
    color: AppColors.muted,
    fontSize: size,
    fontWeight: FontWeight.w900,
  );
}
