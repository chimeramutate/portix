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

  /// The single interaction accent (DESIGN.md).
  final Color cyan;

  /// Text and icons on a [cyan] fill.
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
    bg: Color(0xFF06111D),
    surface: Color(0xFF0B1D30),
    surfaceDark: Color(0xFF071522),
    surfaceCard: Color(0xFF102B47),
    border: Color(0xFF21496F),
    inputBorder: Color(0xFF4A77A2),
    blue: Color(0xFF2D7DFF),
    cyan: Color(0xFF14D7FF),
    onAccent: Color(0xFF06111D),
    green: Color(0xFF20E38A),
    muted: Color(0xFF91A8C2),
    text: Color(0xFFF4F8FF),
    amber: Color(0xFFFFC04D),
    danger: Color(0xFFFF5B83),
    terminal: Color(0xFF020814),
    selected: Color(0xFF143B63),
    selectedSoft: Color(0xFF123455),
    greenTint: Color(0xFF0B3A27),
    amberTint: Color(0xFF3A2D0B),
    dangerTint: Color(0xFF3A1421),
    menu: Color(0xFF1A2535),
  );

  // Accents are darker than in [dark] so they keep contrast on white.
  static const light = AppPalette(
    brightness: Brightness.light,
    bg: Color(0xFFF3F6FA),
    surface: Color(0xFFFFFFFF),
    surfaceDark: Color(0xFFF7F9FC),
    surfaceCard: Color(0xFFE9EFF7),
    border: Color(0xFFCBD6E4),
    inputBorder: Color(0xFF76879E),
    blue: Color(0xFF1F66E0),
    cyan: Color(0xFF036B95),
    onAccent: Color(0xFFFFFFFF),
    green: Color(0xFF077347),
    muted: Color(0xFF52637A),
    text: Color(0xFF0F1B2D),
    amber: Color(0xFF995600),
    danger: Color(0xFFBF2A4E),
    terminal: Color(0xFFF7F9FC),
    selected: Color(0xFFD8E6FB),
    selectedSoft: Color(0xFFE6EEF9),
    greenTint: Color(0xFFDDF4E9),
    amberTint: Color(0xFFFCEFD6),
    dangerTint: Color(0xFFFBE3E8),
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
    focusColor: p.cyan.withValues(alpha: .28),
    scaffoldBackgroundColor: p.bg,
    colorScheme:
        (p.brightness == Brightness.dark
                ? const ColorScheme.dark()
                : const ColorScheme.light())
            .copyWith(
              primary: p.cyan,
              onPrimary: p.onAccent,
              secondary: p.cyan,
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
        fontSize: 20,
        fontWeight: FontWeight.w800,
      ),
      contentTextStyle: TextStyle(
        color: p.text,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.surfaceCard,
      textStyle: TextStyle(
        color: p.text,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    ),
    textTheme: baseTextTheme.copyWith(
      bodyLarge: TextStyle(
        color: p.text,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
      bodyMedium: TextStyle(
        color: p.text,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
      bodySmall: TextStyle(
        color: p.muted,
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
      titleMedium: TextStyle(
        color: p.text,
        fontSize: 14,
        fontWeight: FontWeight.w900,
      ),
      titleLarge: TextStyle(
        color: p.text,
        fontSize: 18,
        fontWeight: FontWeight.w900,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surfaceDark,
      hintStyle: TextStyle(color: p.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: p.inputBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: p.cyan, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 38),
        backgroundColor: p.cyan,
        foregroundColor: p.onAccent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
      ).copyWith(side: focusRingSide(focus: p.text)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style:
          OutlinedButton.styleFrom(
            minimumSize: const Size(0, 38),
            foregroundColor: p.text,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            textStyle: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
          ).copyWith(
            side: focusRingSide(
              focus: p.cyan,
              rest: BorderSide(color: p.inputBorder),
            ),
          ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(side: focusRingSide(focus: p.cyan)),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.cyan,
      ).copyWith(side: focusRingSide(focus: p.cyan)),
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
