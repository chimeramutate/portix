import 'package:flutter/material.dart';

abstract final class AppColors {
  static const bg = Color(0xFF06111D);
  static const surface = Color(0xFF0B1D30);
  static const surfaceDark = Color(0xFF071522);
  static const surfaceCard = Color(0xFF102B47);
  static const border = Color(0xFF21496F);
  static const primaryBlue = Color(0xFF2D7DFF);
  static const cyan = Color(0xFF14D7FF);
  static const green = Color(0xFF20E38A);
  static const muted = Color(0xFF91A8C2);
  static const text = Color(0xFFF4F8FF);
  static const amber = Color(0xFFFFC04D);
  static const danger = Color(0xFFFF5B83);
  static const terminal = Color(0xFF020814);
}

final appTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  scaffoldBackgroundColor: AppColors.bg,
  fontFamily: 'Inter',
  colorScheme: const ColorScheme.dark(
    primary: AppColors.primaryBlue,
    secondary: AppColors.cyan,
    tertiary: AppColors.green,
    surface: AppColors.surface,
    onSurface: AppColors.text,
    outline: AppColors.border,
  ),
  cardTheme: CardThemeData(
    color: AppColors.surface,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: const BorderSide(color: AppColors.border),
    ),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: AppColors.surfaceDark,
    foregroundColor: AppColors.text,
    elevation: 0,
  ),
  textTheme: const TextTheme(
    bodyMedium: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700),
    bodySmall: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600),
    titleMedium: TextStyle(color: AppColors.text, fontWeight: FontWeight.w900),
    titleLarge: TextStyle(color: AppColors.text, fontWeight: FontWeight.w900),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: AppColors.surfaceDark,
    hintStyle: const TextStyle(color: AppColors.muted),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: AppColors.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: AppColors.primaryBlue),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(0, 38),
      backgroundColor: AppColors.primaryBlue,
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(0, 38),
      foregroundColor: AppColors.text,
      side: const BorderSide(color: AppColors.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
    ),
  ),
);
