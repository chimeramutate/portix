import 'package:flutter/widgets.dart';
import 'package:portix/src/core/theme/app_theme.dart';
import 'terminal_themes.dart';

const terminalTextColorSettingKey = 'general.terminal_text_color';
const terminalBackgroundColorSettingKey = 'general.terminal_background_color';
const terminalFontSettingKey = 'general.terminal_font';
const terminalFontSizeSettingKey = 'general.terminal_font_scale';

/// Setting key for the selected terminal color scheme preset.
/// When set to anything other than 'Custom', the preset overrides the
/// individual text/background color settings.
const terminalThemeSettingKey = 'general.terminal_theme';

/// Returns true when the saved [value] selects a preset theme (not 'Custom').
bool isTerminalThemePreset(String? value) =>
    value != null && value != 'Custom' && terminalThemeNames.contains(value);

const terminalFonts = [
  'Monospace',
  'Ubuntu Mono',
  'Fira Code',
  'JetBrains Mono',
  'Roboto Mono',
  'Cascadia Mono',
  'SFMono-Regular',
];

const terminalFontSizes = [
  '11 px',
  '12 px',
  '13 px',
  '14 px',
  '15 px',
  '16 px',
];

Color terminalTextColorFromValue(String? value) {
  switch (value?.trim().toLowerCase() ?? '') {
    case 'green':
      return AppColors.green;
    case 'amber':
      return AppColors.amber;
    case 'cyan':
      return AppColors.cyan;
    case 'blue':
      return AppColors.primaryBlue;
    case 'red':
      return AppColors.danger;
    case 'white':
    default:
      return AppColors.text;
  }
}

Color terminalBackgroundColorFromValue(String? value) {
  switch (value?.trim().toLowerCase().replaceAll(' ', '_') ?? '') {
    case 'dark_blue':
      return const Color(0xFF031426);
    case 'dark_gray':
      return const Color(0xFF111827);
    case 'navy':
      return const Color(0xFF061A2F);
    case 'green':
      return const Color(0xFF052016);
    case 'black':
    default:
      return AppColors.terminal;
  }
}

String terminalFontFamilyFromValue(String? value) {
  switch (value?.trim() ?? '') {
    case 'Ubuntu Mono':
      return 'Ubuntu Mono';
    case 'Fira Code':
      return 'Fira Code';
    case 'JetBrains Mono':
      return 'JetBrains Mono';
    case 'Roboto Mono':
      return 'Roboto Mono';
    case 'Cascadia Mono':
      return 'Cascadia Mono';
    case 'SFMono-Regular':
      return 'SFMono-Regular';
    case 'Monospace':
    default:
      return 'monospace';
  }
}

int terminalFontSizeFromValue(String? value) {
  final match = RegExp(r'^(\d+)\s*px$').firstMatch(value?.trim() ?? '');
  final parsed = match == null ? null : int.tryParse(match.group(1)!);
  return (parsed ?? 13).clamp(10, 32);
}
