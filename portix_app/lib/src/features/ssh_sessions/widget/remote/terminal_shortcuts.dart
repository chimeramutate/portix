import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:xterm/xterm.dart';

const terminalCopyShortcutSettingKey = 'general.terminal_copy_shortcut';
const terminalPasteShortcutSettingKey = 'general.terminal_paste_shortcut';

enum TerminalClipboardShortcut { shiftCtrl, ctrl }

TerminalClipboardShortcut terminalClipboardShortcutFromValue(String? value) {
  switch (value?.trim().toLowerCase()) {
    case 'ctrl':
    case 'ctrl+c':
    case 'ctrl+v':
      return TerminalClipboardShortcut.ctrl;
    case 'shift':
    case 'shift+ctrl':
    case 'shift+ctrl+c':
    case 'shift+ctrl+v':
      return TerminalClipboardShortcut.shiftCtrl;
    default:
      return TerminalClipboardShortcut.shiftCtrl;
  }
}

Map<ShortcutActivator, Intent> terminalShortcutsFor({
  required TerminalClipboardShortcut copyShortcut,
  required TerminalClipboardShortcut pasteShortcut,
  required TerminalController controller,
  required Terminal terminal,
}) {
  // NOTE: Ctrl+A (SelectAll) is intentionally NOT registered here.
  // Many TUI apps (less, vim, emacs, tmux, readline) use Ctrl+A for
  // "go to beginning of line" or other navigation — intercepting it at the
  // Flutter level would break those apps silently.
  final shortcuts = <ShortcutActivator, Intent>{};

  switch (copyShortcut) {
    case TerminalClipboardShortcut.shiftCtrl:
      // Primary copy shortcut: Shift+Ctrl+C — always copies, never conflicts
      // with TUI app shortcuts.
      shortcuts[SingleActivator(
            LogicalKeyboardKey.keyC,
            control: true,
            shift: true,
          )] =
          CopySelectionTextIntent.copy;

      // Secondary: plain Ctrl+C copies ONLY when text is selected so the user
      // can copy highlighted text without switching shortcuts.  When nothing is
      // selected the event falls through so xterm can forward \x03 (SIGINT) to
      // the running process (shell, less, vim, etc.) as normal.
      shortcuts[SingleActivator(LogicalKeyboardKey.keyC, control: true)] =
          const _CtrlCConditionalCopyIntent();

    case TerminalClipboardShortcut.ctrl:
      // In explicit Ctrl-only mode the user accepts that Ctrl+C always copies
      // and never sends SIGINT.
      shortcuts[SingleActivator(LogicalKeyboardKey.keyC, control: true)] =
          CopySelectionTextIntent.copy;
  }

  switch (pasteShortcut) {
    case TerminalClipboardShortcut.shiftCtrl:
      shortcuts[SingleActivator(
        LogicalKeyboardKey.keyV,
        control: true,
        shift: true,
      )] = const PasteTextIntent(
        SelectionChangedCause.keyboard,
      );
    case TerminalClipboardShortcut.ctrl:
      shortcuts[SingleActivator(LogicalKeyboardKey.keyV, control: true)] =
          const PasteTextIntent(SelectionChangedCause.keyboard);
  }

  return shortcuts;
}

/// An intent that copies the current terminal selection when text is selected,
/// and explicitly does nothing (so the key falls through to xterm) when there
/// is no selection.
///
/// Used for Ctrl+C in [TerminalClipboardShortcut.shiftCtrl] mode so the same
/// key can both interrupt processes (no selection → \x03 reaches the shell) and
/// copy highlighted text (selection present → clipboard copy fires).
class _CtrlCConditionalCopyIntent extends Intent {
  const _CtrlCConditionalCopyIntent();
}

/// Action that handles [_CtrlCConditionalCopyIntent].
///
/// * **Selection present** – copies text, returns true from [consumesKey] so
///   the Shortcuts widget marks the key event as handled and xterm does NOT
///   also receive \x03.
/// * **No selection** – does nothing, returns false from [consumesKey] so the
///   Shortcuts widget marks the event as ignored, allowing xterm to forward
///   the raw \x03 (SIGINT) to the running process.
class TerminalCtrlCCopyAction extends Action<_CtrlCConditionalCopyIntent> {
  TerminalCtrlCCopyAction({required this.controller});

  final TerminalController controller;

  bool get _hasSelection => controller.selection != null;

  @override
  Object? invoke(_CtrlCConditionalCopyIntent intent) {
    if (!_hasSelection) return null;
    Actions.maybeInvoke(primaryFocus!.context!, CopySelectionTextIntent.copy);
    return null;
  }

  @override
  bool isEnabled(_CtrlCConditionalCopyIntent intent) => true;

  /// Consume the key only when there is something to copy.  When false, the
  /// Shortcuts widget propagates the event as unhandled → xterm gets \x03.
  @override
  bool consumesKey(_CtrlCConditionalCopyIntent intent) => _hasSelection;
}

const minTerminalFontSize = 8.0;
const maxTerminalFontSize = 32.0;

/// Font size after a zoom shortcut, or null when [key] is not one.
/// macOS: Cmd + `=` / `-` / `0`. Elsewhere Ctrl+Shift, because plain
/// Ctrl+`-` is `^_` (readline undo) and must reach the shell. `0` returns
/// to [base], the size from Settings.
double? terminalZoomFontSize(
  LogicalKeyboardKey key, {
  required double current,
  required double base,
  required bool meta,
  required bool control,
  required bool shift,
  required bool isMacOS,
}) {
  final modifier = isMacOS ? meta && !control : control && shift && !meta;
  if (!modifier) return null;
  final next = switch (key) {
    LogicalKeyboardKey.equal || LogicalKeyboardKey.add => current + 1,
    LogicalKeyboardKey.numpadAdd => current + 1,
    LogicalKeyboardKey.minus || LogicalKeyboardKey.underscore => current - 1,
    LogicalKeyboardKey.numpadSubtract => current - 1,
    LogicalKeyboardKey.digit0 || LogicalKeyboardKey.parenthesisRight => base,
    LogicalKeyboardKey.numpad0 => base,
    _ => null,
  };
  return next?.clamp(minTerminalFontSize, maxTerminalFontSize);
}
