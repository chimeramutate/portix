import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

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
}) {
  final shortcuts = <ShortcutActivator, Intent>{
    SingleActivator(LogicalKeyboardKey.keyA, control: true):
        const SelectAllTextIntent(SelectionChangedCause.keyboard),
  };
  switch (copyShortcut) {
    case TerminalClipboardShortcut.shiftCtrl:
      shortcuts[SingleActivator(
            LogicalKeyboardKey.keyC,
            control: true,
            shift: true,
          )] =
          CopySelectionTextIntent.copy;
    case TerminalClipboardShortcut.ctrl:
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
