import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/features/ssh_sessions/widget/remote/terminal_settings.dart';
import 'package:portix/src/features/ssh_sessions/widget/remote/terminal_shortcuts.dart';
import 'package:xterm/xterm.dart';

void main() {
  test('parses terminal clipboard shortcut settings', () {
    expect(
      terminalClipboardShortcutFromValue('Shift+Ctrl+C'),
      TerminalClipboardShortcut.shiftCtrl,
    );
    expect(
      terminalClipboardShortcutFromValue('Ctrl+C'),
      TerminalClipboardShortcut.ctrl,
    );
    expect(
      terminalClipboardShortcutFromValue('Ctrl+V'),
      TerminalClipboardShortcut.ctrl,
    );
    expect(
      terminalClipboardShortcutFromValue('Shift+Ctrl+V'),
      TerminalClipboardShortcut.shiftCtrl,
    );
  });

  test(
    'builds configurable terminal shortcuts without intercepting Shift+G',
    () {
      final controller = TerminalController();
      final terminal = Terminal();
      final shortcuts = terminalShortcutsFor(
        copyShortcut: TerminalClipboardShortcut.shiftCtrl,
        pasteShortcut: TerminalClipboardShortcut.ctrl,
        controller: controller,
        terminal: terminal,
      );

      expect(shortcuts, isNotEmpty);
      expect(
        shortcuts.keys.any(
          (activator) =>
              activator is SingleActivator &&
              activator.trigger == LogicalKeyboardKey.keyG &&
              activator.shift,
        ),
        isFalse,
      );
      expect(
        shortcuts.keys.any(
          (activator) =>
              activator is SingleActivator &&
              activator.trigger == LogicalKeyboardKey.keyC,
        ),
        isTrue,
      );
      expect(
        shortcuts.keys.any(
          (activator) =>
              activator is SingleActivator &&
              activator.trigger == LogicalKeyboardKey.keyV,
        ),
        isTrue,
      );
    },
  );

  test('parses terminal appearance settings', () {
    expect(terminalTextColorFromValue('Green'), const Color(0xFF20E38A));
    expect(
      terminalBackgroundColorFromValue('Dark Blue'),
      const Color(0xFF031426),
    );
    expect(terminalFontFamilyFromValue('Fira Code'), 'Fira Code');
    expect(terminalFontSizeFromValue('15 px'), 15);
  });
}
