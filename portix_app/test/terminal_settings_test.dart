import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/core/theme/app_theme.dart';
import 'package:portix/src/features/ssh_sessions/widget/remote/terminal_settings.dart';
import 'package:portix/src/features/ssh_sessions/widget/remote/terminal_shortcuts.dart';
import 'package:xterm/xterm.dart';

void main() {
  test('parses saved shortcuts, including the old Settings values', () {
    final copy = parseBinding('Shift+Ctrl+C')!;
    expect(copy.trigger, LogicalKeyboardKey.keyC);
    expect(copy.control && copy.shift && !copy.alt && !copy.meta, isTrue);
    expect(formatBinding(copy), 'Ctrl+Shift+C');
    expect(formatBinding(parseBinding('Ctrl+Alt+F5')!), 'Ctrl+Alt+F5');
    expect(parseBinding('Ctrl++')!.trigger, LogicalKeyboardKey.add);
    expect(parseBinding('Hyper+C'), isNull);
    expect(parseBinding(''), isNull);
  });

  test('falls back to defaults for unset or broken bindings', () {
    final bindings = terminalBindingsFrom({
      TerminalCommand.find.settingKey: 'Ctrl+Alt+G',
      TerminalCommand.snippets.settingKey: 'nonsense+',
    });
    expect(formatBinding(bindings[TerminalCommand.find]!), 'Ctrl+Alt+G');
    expect(
      formatBinding(bindings[TerminalCommand.snippets]!),
      formatBinding(TerminalCommand.snippets.defaultBinding),
    );
  });

  test('zoom matches = and + as the same key', () {
    const zoomIn = SingleActivator(
      LogicalKeyboardKey.equal,
      control: true,
      shift: true,
    );
    bool match(LogicalKeyboardKey key, {bool shift = true}) => bindingMatches(
      zoomIn,
      key,
      control: true,
      shift: shift,
      alt: false,
      meta: false,
    );
    expect(match(LogicalKeyboardKey.equal), isTrue);
    expect(match(LogicalKeyboardKey.add), isTrue);
    expect(match(LogicalKeyboardKey.equal, shift: false), isFalse);
    expect(match(LogicalKeyboardKey.minus), isFalse);
  });

  test(
    'builds configurable terminal shortcuts without intercepting Shift+G',
    () {
      final controller = TerminalController();
      final terminal = Terminal();
      final shortcuts = terminalShortcutsFor(
        copyShortcut: terminalDefaultCopyBinding,
        pasteShortcut: terminalDefaultPasteBinding,
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
    expect(terminalTextColorFromValue('Green'), AppColors.green);
    expect(
      terminalBackgroundColorFromValue('Dark Blue'),
      const Color(0xFF031426),
    );
    expect(terminalFontFamilyFromValue('Fira Code'), 'Fira Code');
    expect(terminalFontSizeFromValue('15 px'), 15);
  });
}
