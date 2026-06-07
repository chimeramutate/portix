import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

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
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color color;
  final Color borderColor;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
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
  return GoogleFonts.inter(
    color: AppColors.text,
    fontSize: size,
    fontWeight: FontWeight.w900,
  );
}

TextStyle portixMuted([double size = 12]) {
  return GoogleFonts.inter(
    color: AppColors.muted,
    fontSize: size,
    fontWeight: FontWeight.w600,
  );
}

TextStyle portixLabel([double size = 12]) {
  return GoogleFonts.inter(
    color: AppColors.muted,
    fontSize: size,
    fontWeight: FontWeight.w900,
  );
}
