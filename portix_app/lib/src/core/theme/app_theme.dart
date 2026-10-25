import 'package:flutter/material.dart';

/// The app's colors for one brightness.
class AppPalette {
  const AppPalette({
    required this.brightness,
    required this.bg,
    required this.surface,
    required this.surfaceDark,
    required this.surfaceCard,
    required this.border,
    required this.inputBorder,
    required this.blue,
    required this.cyan,
    required this.accent,
    required this.onAccent,
    required this.green,
    required this.muted,
    required this.text,
    required this.amber,
    required this.danger,
    required this.terminal,
    required this.selected,
    required this.selectedSoft,
    required this.greenTint,
    required this.amberTint,
    required this.dangerTint,
    required this.menu,
  });

  final Brightness brightness;
  final Color bg;
  final Color surface;
  final Color surfaceDark;
  final Color surfaceCard;
  final Color border;

  /// Boundary of inputs and outlined controls: 3:1 against their fill.
  final Color inputBorder;

  /// Categorical blue (profile color, file type); not an accent.
  final Color blue;

  /// Categorical cyan (profile color, file type, log level); not an accent.
  final Color cyan;

  /// The single interaction accent (DESIGN.md).
  final Color accent;

  /// Text and icons on an [accent] fill.
  final Color onAccent;
  final Color green;
  final Color muted;
  final Color text;
  final Color amber;
  final Color danger;
  final Color terminal;

  /// Background of a selected/active item (tab, row, card).
  final Color selected;

  /// A lighter selection: hover, highlighted cards, info chips.
  final Color selectedSoft;
  final Color greenTint;
  final Color amberTint;
  final Color dangerTint;

  /// Popup/context menu background.
  final Color menu;

  static const dark = AppPalette(
    brightness: Brightness.dark,
    bg: Color(0xFF0B1120),
    surface: Color(0xFF131B2E),
    surfaceDark: Color(0xFF0F172A),
    surfaceCard: Color(0xFF1B2336),
    border: Color(0xFF273349),
    inputBorder: Color(0xFF74839A),
    blue: Color(0xFF60A5FA),
    cyan: Color(0xFF22D3EE),
    accent: Color(0xFF22C55E),
    onAccent: Color(0xFF0B1120),
    green: Color(0xFF4ADE80),
    muted: Color(0xFF94A3B8),
    text: Color(0xFFF8FAFC),
    amber: Color(0xFFFBBF24),
    danger: Color(0xFFF87171),
    terminal: Color(0xFF0A0F1C),
    selected: Color(0xFF243049),
    selectedSoft: Color(0xFF1C2539),
    greenTint: Color(0xFF0F2E1D),
    amberTint: Color(0xFF33280A),
    dangerTint: Color(0xFF3A1618),
    menu: Color(0xFF1E293B),
  );

  // Accents are darker than in [dark] so they keep contrast on white.
  static const light = AppPalette(
    brightness: Brightness.light,
    bg: Color(0xFFF8FAFC),
    surface: Color(0xFFFFFFFF),
    surfaceDark: Color(0xFFF1F5F9),
    surfaceCard: Color(0xFFEEF2F6),
    border: Color(0xFFE2E8F0),
    inputBorder: Color(0xFF64748B),
    blue: Color(0xFF2563EB),
    cyan: Color(0xFF0E7490),
    accent: Color(0xFF166534),
    onAccent: Color(0xFFFFFFFF),
    green: Color(0xFF166534),
    muted: Color(0xFF475569),
    text: Color(0xFF0F172A),
    amber: Color(0xFF92400E),
    danger: Color(0xFFB91C1C),
    terminal: Color(0xFFF8FAFC),
    selected: Color(0xFFE2E8F0),
    selectedSoft: Color(0xFFF1F5F9),
    greenTint: Color(0xFFDCFCE7),
    amberTint: Color(0xFFFEF3C7),
    dangerTint: Color(0xFFFEE2E2),
    menu: Color(0xFFFFFFFF),
  );
}

/// The current palette, following the OS light/dark setting (see
/// [FollowSystemBrightness]); there is no in-app switch.
abstract final class AppColors {
  static AppPalette palette = AppPalette.dark;

  static Color get bg => palette.bg;
  static Color get surface => palette.surface;
  static Color get surfaceDark => palette.surfaceDark;
  static Color get surfaceCard => palette.surfaceCard;
  static Color get border => palette.border;
  static Color get inputBorder => palette.inputBorder;
  static Color get blue => palette.blue;
  static Color get onAccent => palette.onAccent;
  static Color get cyan => palette.cyan;
  static Color get accent => palette.accent;
  static Color get green => palette.green;
  static Color get muted => palette.muted;
  static Color get text => palette.text;
  static Color get amber => palette.amber;
  static Color get danger => palette.danger;
  static Color get terminal => palette.terminal;
  static Color get selected => palette.selected;
  static Color get selectedSoft => palette.selectedSoft;
  static Color get greenTint => palette.greenTint;
  static Color get amberTint => palette.amberTint;
  static Color get dangerTint => palette.dangerTint;
  static Color get menu => palette.menu;
}

/// Keeps [AppColors] in step with the OS light/dark setting and rebuilds
/// [child] when it changes. Widgets keep their state.
class FollowSystemBrightness extends StatefulWidget {
  const FollowSystemBrightness({required this.child, super.key});

  final Widget child;

  @override
  State<FollowSystemBrightness> createState() => _FollowSystemBrightnessState();
}

class _FollowSystemBrightnessState extends State<FollowSystemBrightness>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _apply();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _apply() {
    AppColors.palette =
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.light
        ? AppPalette.light
        : AppPalette.dark;
  }

  @override
  void didChangePlatformBrightness() {
    _apply();
    // Colors are read in build methods, also of widgets that would
    // not rebuild on their own: mark the whole subtree.
    void rebuild(Element element) {
      element.markNeedsBuild();
      element.visitChildren(rebuild);
    }

    (context as Element).visitChildren(rebuild);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

final appTheme = buildAppTheme(AppPalette.dark);
final appLightTheme = buildAppTheme(AppPalette.light);

ThemeData buildAppTheme(AppPalette p) {
  final baseTextTheme = ThemeData(brightness: p.brightness).textTheme;
  return ThemeData(
    useMaterial3: true,
    brightness: p.brightness,
    visualDensity: VisualDensity.compact,
    focusColor: p.accent.withValues(alpha: .28),
    scaffoldBackgroundColor: p.bg,
    colorScheme:
        (p.brightness == Brightness.dark
                ? const ColorScheme.dark()
                : const ColorScheme.light())
            .copyWith(
              primary: p.accent,
              onPrimary: p.onAccent,
              secondary: p.accent,
              tertiary: p.green,
              surface: p.surface,
              onSurface: p.text,
              outline: p.border,
            ),
    cardTheme: CardThemeData(
      color: p.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: p.border),
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: p.surfaceDark,
      foregroundColor: p.text,
      elevation: 0,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      titleTextStyle: TextStyle(
        color: p.text,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      contentTextStyle: TextStyle(
        color: p.text,
        fontSize: 13,
        fontWeight: FontWeight.w400,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.menu,
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: p.border),
      ),
      textStyle: TextStyle(
        color: p.text,
        fontSize: 13,
        fontWeight: FontWeight.w400,
      ),
    ),
    dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: p.menu,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: p.border),
      ),
      textStyle: TextStyle(color: p.text, fontSize: 12),
    ),
    textTheme: baseTextTheme.copyWith(
      bodyLarge: TextStyle(
        color: p.text,
        fontSize: 13,
        fontWeight: FontWeight.w400,
      ),
      bodyMedium: TextStyle(
        color: p.text,
        fontSize: 12,
        fontWeight: FontWeight.w400,
      ),
      bodySmall: TextStyle(
        color: p.muted,
        fontSize: 11,
        fontWeight: FontWeight.w400,
      ),
      titleMedium: TextStyle(
        color: p.text,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      titleLarge: TextStyle(
        color: p.text,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surfaceDark,
      hintStyle: TextStyle(color: p.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: p.inputBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: p.accent, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 32),
        backgroundColor: p.accent,
        foregroundColor: p.onAccent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
      ).copyWith(side: focusRingSide(focus: p.text)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style:
          OutlinedButton.styleFrom(
            minimumSize: const Size(0, 32),
            foregroundColor: p.text,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            textStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
          ).copyWith(
            side: focusRingSide(
              focus: p.accent,
              rest: BorderSide(color: p.inputBorder),
            ),
          ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(side: focusRingSide(focus: p.accent)),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.accent,
      ).copyWith(side: focusRingSide(focus: p.accent)),
    ),
  );
}

/// A 2px ring while keyboard-focused, so focus never relies on a faint overlay.
WidgetStateProperty<BorderSide?> focusRingSide({
  required Color focus,
  BorderSide? rest,
}) => WidgetStateProperty.resolveWith(
  (states) => states.contains(WidgetState.focused)
      ? BorderSide(color: focus, width: 2)
      : rest,
);
