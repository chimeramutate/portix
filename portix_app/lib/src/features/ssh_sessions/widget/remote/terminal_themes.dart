import 'package:xterm/xterm.dart';
import 'package:flutter/widgets.dart';

/// All built-in terminal color scheme names.
/// The first entry is the default (Portix dark).
const terminalThemeNames = [
  'Portix',
  'Dracula',
  'Nord',
  'Solarized Dark',
  'Solarized Light',
  'One Dark',
  'Gruvbox Dark',
  'Monokai',
  'Tokyo Night',
  'Catppuccin Mocha',
];

/// Returns the [TerminalTheme] for the given [name].
/// Falls back to [portixBuiltinTheme] for unknown names.
TerminalTheme terminalThemeByName(String? name) {
  return switch (name?.trim() ?? 'Portix') {
    'Dracula' => _dracula,
    'Nord' => _nord,
    'Solarized Dark' => _solarizedDark,
    'Solarized Light' => _solarizedLight,
    'One Dark' => _oneDark,
    'Gruvbox Dark' => _gruvboxDark,
    'Monokai' => _monokai,
    'Tokyo Night' => _tokyoNight,
    'Catppuccin Mocha' => _catppuccinMocha,
    _ => portixBuiltinTheme,
  };
}

// ── Portix (default) ──────────────────────────────────────────────────────

const portixBuiltinTheme = TerminalTheme(
  cursor: Color(0xFF39D353),
  selection: Color(0x663A78B7),
  foreground: Color(0xFFD0E3FF),
  background: Color(0xFF060D18),
  black: Color(0xFF020814),
  red: Color(0xFFFF5E7A),
  green: Color(0xFF39D353),
  yellow: Color(0xFFFFC145),
  blue: Color(0xFF3A78B7),
  magenta: Color(0xFFFF6BD6),
  cyan: Color(0xFF41E0F0),
  white: Color(0xFFD0E3FF),
  brightBlack: Color(0xFF5E7899),
  brightRed: Color(0xFFFF7C9B),
  brightGreen: Color(0xFF49F5A5),
  brightYellow: Color(0xFFFFD37A),
  brightBlue: Color(0xFF69A3FF),
  brightMagenta: Color(0xFFFF95E2),
  brightCyan: Color(0xFF71E9FF),
  brightWhite: Color(0xFFFFFFFF),
  searchHitBackground: Color(0x66406200),
  searchHitBackgroundCurrent: Color(0xAA805800),
  searchHitForeground: Color(0xFFD0E3FF),
);

// ── Dracula ───────────────────────────────────────────────────────────────
// https://draculatheme.com/contribute

const _dracula = TerminalTheme(
  cursor: Color(0xFFF8F8F2),
  selection: Color(0x6644475A),
  foreground: Color(0xFFF8F8F2),
  background: Color(0xFF282A36),
  black: Color(0xFF21222C),
  red: Color(0xFFFF5555),
  green: Color(0xFF50FA7B),
  yellow: Color(0xFFF1FA8C),
  blue: Color(0xFFBD93F9),
  magenta: Color(0xFFFF79C6),
  cyan: Color(0xFF8BE9FD),
  white: Color(0xFFF8F8F2),
  brightBlack: Color(0xFF6272A4),
  brightRed: Color(0xFFFF6E6E),
  brightGreen: Color(0xFF69FF94),
  brightYellow: Color(0xFFFFFF87),
  brightBlue: Color(0xFFD6ACFF),
  brightMagenta: Color(0xFFFF92DF),
  brightCyan: Color(0xFFA4FFFF),
  brightWhite: Color(0xFFFFFFFF),
  searchHitBackground: Color(0x66F1FA8C),
  searchHitBackgroundCurrent: Color(0xAAF1FA8C),
  searchHitForeground: Color(0xFF282A36),
);

// ── Nord ──────────────────────────────────────────────────────────────────
// https://www.nordtheme.com

const _nord = TerminalTheme(
  cursor: Color(0xFFD8DEE9),
  selection: Color(0x664C566A),
  foreground: Color(0xFFD8DEE9),
  background: Color(0xFF2E3440),
  black: Color(0xFF3B4252),
  red: Color(0xFFBF616A),
  green: Color(0xFFA3BE8C),
  yellow: Color(0xFFEBCB8B),
  blue: Color(0xFF81A1C1),
  magenta: Color(0xFFB48EAD),
  cyan: Color(0xFF88C0D0),
  white: Color(0xFFE5E9F0),
  brightBlack: Color(0xFF4C566A),
  brightRed: Color(0xFFBF616A),
  brightGreen: Color(0xFFA3BE8C),
  brightYellow: Color(0xFFEBCB8B),
  brightBlue: Color(0xFF81A1C1),
  brightMagenta: Color(0xFFB48EAD),
  brightCyan: Color(0xFF8FBCBB),
  brightWhite: Color(0xFFECEFF4),
  searchHitBackground: Color(0x66EBCB8B),
  searchHitBackgroundCurrent: Color(0xAAEBCB8B),
  searchHitForeground: Color(0xFF2E3440),
);

// ── Solarized Dark ────────────────────────────────────────────────────────
// https://ethanschoonover.com/solarized

const _solarizedDark = TerminalTheme(
  cursor: Color(0xFF839496),
  selection: Color(0x66073642),
  foreground: Color(0xFF839496),
  background: Color(0xFF002B36),
  black: Color(0xFF073642),
  red: Color(0xFFDC322F),
  green: Color(0xFF859900),
  yellow: Color(0xFFB58900),
  blue: Color(0xFF268BD2),
  magenta: Color(0xFFD33682),
  cyan: Color(0xFF2AA198),
  white: Color(0xFFEEE8D5),
  // Canonical base03 equals the background, which hides dim/ghost text
  // (e.g. zsh-autosuggestions) — use base01 so it stays visible.
  brightBlack: Color(0xFF586E75),
  brightRed: Color(0xFFCB4B16),
  brightGreen: Color(0xFF586E75),
  brightYellow: Color(0xFF657B83),
  brightBlue: Color(0xFF839496),
  brightMagenta: Color(0xFF6C71C4),
  brightCyan: Color(0xFF93A1A1),
  brightWhite: Color(0xFFFDF6E3),
  searchHitBackground: Color(0x66B58900),
  searchHitBackgroundCurrent: Color(0xAAB58900),
  searchHitForeground: Color(0xFFFDF6E3),
);

// ── Solarized Light ───────────────────────────────────────────────────────

const _solarizedLight = TerminalTheme(
  cursor: Color(0xFF657B83),
  selection: Color(0x66EEE8D5),
  foreground: Color(0xFF657B83),
  background: Color(0xFFFDF6E3),
  black: Color(0xFF073642),
  red: Color(0xFFDC322F),
  green: Color(0xFF859900),
  yellow: Color(0xFFB58900),
  blue: Color(0xFF268BD2),
  magenta: Color(0xFFD33682),
  cyan: Color(0xFF2AA198),
  white: Color(0xFFEEE8D5),
  brightBlack: Color(0xFF002B36),
  brightRed: Color(0xFFCB4B16),
  brightGreen: Color(0xFF586E75),
  brightYellow: Color(0xFF657B83),
  brightBlue: Color(0xFF839496),
  brightMagenta: Color(0xFF6C71C4),
  brightCyan: Color(0xFF93A1A1),
  brightWhite: Color(0xFFFDF6E3),
  searchHitBackground: Color(0x66B58900),
  searchHitBackgroundCurrent: Color(0xAAB58900),
  searchHitForeground: Color(0xFF002B36),
);

// ── One Dark ──────────────────────────────────────────────────────────────
// Atom One Dark — https://github.com/atom/atom

const _oneDark = TerminalTheme(
  cursor: Color(0xFFABB2BF),
  selection: Color(0x663E4451),
  foreground: Color(0xFFABB2BF),
  background: Color(0xFF282C34),
  black: Color(0xFF282C34),
  red: Color(0xFFE06C75),
  green: Color(0xFF98C379),
  yellow: Color(0xFFE5C07B),
  blue: Color(0xFF61AFEF),
  magenta: Color(0xFFC678DD),
  cyan: Color(0xFF56B6C2),
  white: Color(0xFFABB2BF),
  brightBlack: Color(0xFF5C6370),
  brightRed: Color(0xFFE06C75),
  brightGreen: Color(0xFF98C379),
  brightYellow: Color(0xFFE5C07B),
  brightBlue: Color(0xFF61AFEF),
  brightMagenta: Color(0xFFC678DD),
  brightCyan: Color(0xFF56B6C2),
  brightWhite: Color(0xFFFFFFFF),
  searchHitBackground: Color(0x66E5C07B),
  searchHitBackgroundCurrent: Color(0xAAE5C07B),
  searchHitForeground: Color(0xFF282C34),
);

// ── Gruvbox Dark ──────────────────────────────────────────────────────────
// https://github.com/morhetz/gruvbox

const _gruvboxDark = TerminalTheme(
  cursor: Color(0xFFEBDBB2),
  selection: Color(0x663C3836),
  foreground: Color(0xFFEBDBB2),
  background: Color(0xFF282828),
  black: Color(0xFF282828),
  red: Color(0xFFCC241D),
  green: Color(0xFF98971A),
  yellow: Color(0xFFD79921),
  blue: Color(0xFF458588),
  magenta: Color(0xFFB16286),
  cyan: Color(0xFF689D6A),
  white: Color(0xFFA89984),
  brightBlack: Color(0xFF928374),
  brightRed: Color(0xFFFB4934),
  brightGreen: Color(0xFFB8BB26),
  brightYellow: Color(0xFFFABD2F),
  brightBlue: Color(0xFF83A598),
  brightMagenta: Color(0xFFD3869B),
  brightCyan: Color(0xFF8EC07C),
  brightWhite: Color(0xFFEBDBB2),
  searchHitBackground: Color(0x66D79921),
  searchHitBackgroundCurrent: Color(0xAAD79921),
  searchHitForeground: Color(0xFF282828),
);

// ── Monokai ───────────────────────────────────────────────────────────────
// https://monokai.pro

const _monokai = TerminalTheme(
  cursor: Color(0xFFF8F8F2),
  selection: Color(0x6649483E),
  foreground: Color(0xFFF8F8F2),
  background: Color(0xFF272822),
  black: Color(0xFF272822),
  red: Color(0xFFF92672),
  green: Color(0xFFA6E22E),
  yellow: Color(0xFFF4BF75),
  blue: Color(0xFF66D9E8),
  magenta: Color(0xFFAE81FF),
  cyan: Color(0xFFA1EFE4),
  white: Color(0xFFF8F8F2),
  brightBlack: Color(0xFF75715E),
  brightRed: Color(0xFFF92672),
  brightGreen: Color(0xFFA6E22E),
  brightYellow: Color(0xFFF4BF75),
  brightBlue: Color(0xFF66D9E8),
  brightMagenta: Color(0xFFAE81FF),
  brightCyan: Color(0xFFA1EFE4),
  brightWhite: Color(0xFFF9F8F5),
  searchHitBackground: Color(0x66F4BF75),
  searchHitBackgroundCurrent: Color(0xAAF4BF75),
  searchHitForeground: Color(0xFF272822),
);

// ── Tokyo Night ───────────────────────────────────────────────────────────
// https://github.com/enkia/tokyo-night-vscode-theme

const _tokyoNight = TerminalTheme(
  cursor: Color(0xFFC0CAF5),
  selection: Color(0x6628344A),
  foreground: Color(0xFFC0CAF5),
  background: Color(0xFF1A1B26),
  black: Color(0xFF15161E),
  red: Color(0xFFF7768E),
  green: Color(0xFF9ECE6A),
  yellow: Color(0xFFE0AF68),
  blue: Color(0xFF7AA2F7),
  magenta: Color(0xFFBB9AF7),
  cyan: Color(0xFF7DCFFF),
  white: Color(0xFFA9B1D6),
  brightBlack: Color(0xFF414868),
  brightRed: Color(0xFFF7768E),
  brightGreen: Color(0xFF9ECE6A),
  brightYellow: Color(0xFFE0AF68),
  brightBlue: Color(0xFF7AA2F7),
  brightMagenta: Color(0xFFBB9AF7),
  brightCyan: Color(0xFF7DCFFF),
  brightWhite: Color(0xFFC0CAF5),
  searchHitBackground: Color(0x66E0AF68),
  searchHitBackgroundCurrent: Color(0xAAE0AF68),
  searchHitForeground: Color(0xFF1A1B26),
);

// ── Catppuccin Mocha ──────────────────────────────────────────────────────
// https://github.com/catppuccin/catppuccin

const _catppuccinMocha = TerminalTheme(
  cursor: Color(0xFFCDD6F4),
  selection: Color(0x66313244),
  foreground: Color(0xFFCDD6F4),
  background: Color(0xFF1E1E2E),
  black: Color(0xFF45475A),
  red: Color(0xFFF38BA8),
  green: Color(0xFFA6E3A1),
  yellow: Color(0xFFF9E2AF),
  blue: Color(0xFF89B4FA),
  magenta: Color(0xFFCBA6F7),
  cyan: Color(0xFF89DCEB),
  white: Color(0xFFBAC2DE),
  brightBlack: Color(0xFF585B70),
  brightRed: Color(0xFFF38BA8),
  brightGreen: Color(0xFFA6E3A1),
  brightYellow: Color(0xFFF9E2AF),
  brightBlue: Color(0xFF89B4FA),
  brightMagenta: Color(0xFFCBA6F7),
  brightCyan: Color(0xFF89DCEB),
  brightWhite: Color(0xFFA6ADC8),
  searchHitBackground: Color(0x66F9E2AF),
  searchHitBackgroundCurrent: Color(0xAAF9E2AF),
  searchHitForeground: Color(0xFF1E1E2E),
);
