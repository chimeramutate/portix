import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/features/app_menu/keyboard_shortcuts_dialog.dart';
import 'package:portix/src/features/ssh_sessions/widget/remote/terminal_shortcuts.dart';

void main() {
  final defaults = terminalBindingsFrom(const {});

  test('a shortcut needs Ctrl, Alt or Cmd', () {
    expect(
      keyError(
        TerminalCommand.find,
        const SingleActivator(LogicalKeyboardKey.keyF, shift: true),
        defaults,
      ),
      contains('Add Ctrl'),
    );
  });

  test('a shortcut already used by another command is refused', () {
    expect(
      keyError(
        TerminalCommand.find,
        TerminalCommand.snippets.defaultBinding,
        defaults,
      ),
      contains('Snippets'),
    );
    expect(
      keyError(
        TerminalCommand.find,
        const SingleActivator(LogicalKeyboardKey.keyG, alt: true),
        defaults,
      ),
      isNull,
    );
  });
}
