part of '../terminal_workspace_view.dart';

const portixTerminalTheme = TerminalTheme(
  cursor: AppColors.green,
  selection: Color(0x663A78B7),
  foreground: AppColors.text,
  background: AppColors.terminal,
  black: Color(0xFF020814),
  red: AppColors.danger,
  green: AppColors.green,
  yellow: AppColors.amber,
  blue: AppColors.primaryBlue,
  magenta: Color(0xFFFF6BD6),
  cyan: AppColors.cyan,
  white: AppColors.text,
  brightBlack: AppColors.muted,
  brightRed: Color(0xFFFF7C9B),
  brightGreen: Color(0xFF49F5A5),
  brightYellow: Color(0xFFFFD37A),
  brightBlue: Color(0xFF69A3FF),
  brightMagenta: Color(0xFFFF95E2),
  brightCyan: Color(0xFF71E9FF),
  brightWhite: Colors.white,
  searchHitBackground: Color(0x66406200),
  searchHitBackgroundCurrent: Color(0xAA805800),
  searchHitForeground: AppColors.text,
);

/// Builds a [TerminalTheme] with cursor and selection tinted by the
/// profile's chosen [domain.ProfileColor]. All other colors remain the
/// same as [portixTerminalTheme].
TerminalTheme terminalThemeForProfile(domain.SshProfile? profile) {
  if (profile == null) return portixTerminalTheme;
  final accentColor = switch (profile.color) {
    domain.ProfileColor.green => AppColors.green,
    domain.ProfileColor.cyan => AppColors.cyan,
    domain.ProfileColor.blue => AppColors.primaryBlue,
    domain.ProfileColor.pink => AppColors.danger,
    domain.ProfileColor.amber => AppColors.amber,
  };
  return TerminalTheme(
    cursor: accentColor,
    selection: accentColor.withValues(alpha: .28),
    foreground: AppColors.text,
    background: AppColors.terminal,
    black: const Color(0xFF020814),
    red: AppColors.danger,
    green: AppColors.green,
    yellow: AppColors.amber,
    blue: AppColors.primaryBlue,
    magenta: const Color(0xFFFF6BD6),
    cyan: AppColors.cyan,
    white: AppColors.text,
    brightBlack: AppColors.muted,
    brightRed: const Color(0xFFFF7C9B),
    brightGreen: const Color(0xFF49F5A5),
    brightYellow: const Color(0xFFFFD37A),
    brightBlue: const Color(0xFF69A3FF),
    brightMagenta: const Color(0xFFFF95E2),
    brightCyan: const Color(0xFF71E9FF),
    brightWhite: Colors.white,
    searchHitBackground: const Color(0x66406200),
    searchHitBackgroundCurrent: const Color(0xAA805800),
    searchHitForeground: AppColors.text,
  );
}
