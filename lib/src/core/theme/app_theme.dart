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

const _fontFamily = 'Inter';

final _baseTextTheme = ThemeData(brightness: Brightness.dark).textTheme.apply(
  fontFamily: _fontFamily,
);

final appTheme = ThemeData(
  useMaterial3: true,
  brightness: Brightness.dark,
  visualDensity: VisualDensity.compact,
  scaffoldBackgroundColor: AppColors.bg,
  fontFamily: _fontFamily,
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
  dialogTheme: DialogThemeData(
    backgroundColor: AppColors.surface,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    titleTextStyle: const TextStyle(
      fontFamily: _fontFamily,
      color: AppColors.text,
      fontSize: 20,
      fontWeight: FontWeight.w800,
    ),
    contentTextStyle: const TextStyle(
      fontFamily: _fontFamily,
      color: AppColors.text,
      fontSize: 13,
      fontWeight: FontWeight.w600,
    ),
  ),
  popupMenuTheme: const PopupMenuThemeData(
    color: AppColors.surfaceCard,
    textStyle: TextStyle(
      fontFamily: _fontFamily,
      color: AppColors.text,
      fontSize: 12,
      fontWeight: FontWeight.w700,
    ),
  ),
  textTheme: _baseTextTheme.copyWith(
    bodyLarge: const TextStyle(
      fontFamily: _fontFamily,
      color: AppColors.text,
      fontSize: 13,
      fontWeight: FontWeight.w700,
    ),
    bodyMedium: const TextStyle(
      fontFamily: _fontFamily,
      color: AppColors.text,
      fontSize: 12,
      fontWeight: FontWeight.w700,
    ),
    bodySmall: const TextStyle(
      fontFamily: _fontFamily,
      color: AppColors.muted,
      fontSize: 11,
      fontWeight: FontWeight.w600,
    ),
    titleMedium: const TextStyle(
      fontFamily: _fontFamily,
      color: AppColors.text,
      fontSize: 14,
      fontWeight: FontWeight.w900,
    ),
    titleLarge: const TextStyle(
      fontFamily: _fontFamily,
      color: AppColors.text,
      fontSize: 18,
      fontWeight: FontWeight.w900,
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: AppColors.surfaceDark,
    hintStyle: const TextStyle(fontFamily: _fontFamily, color: AppColors.muted),
    contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
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
      textStyle: const TextStyle(
        fontFamily: _fontFamily,
        fontWeight: FontWeight.w800,
        fontSize: 12,
      ),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(0, 38),
      foregroundColor: AppColors.text,
      side: const BorderSide(color: AppColors.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      textStyle: const TextStyle(
        fontFamily: _fontFamily,
        fontWeight: FontWeight.w800,
        fontSize: 12,
      ),
    ),
  ),
);
