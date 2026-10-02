import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/connection_manager/session_models.dart';
import 'package:portix/src/features/ssh_sessions/controller/terminal_suggestion_controller.dart';
import 'package:portix/src/features/ssh_sessions/widget/remote/terminal_settings.dart';
import 'package:portix/src/features/ssh_sessions/widget/remote/terminal_shortcuts.dart';
import 'package:xterm/xterm.dart';

void main() {
  const sessionId = 'ssh-session';

  test('never suggests previously typed commands', () {
    final controller = TerminalSuggestionController();

    controller.handleInput(sessionId, 'git status');
    controller.handleInput(sessionId, '\r');
    controller.handleInput(sessionId, 'gi');

    expect(controller.candidatesFor(sessionId), isEmpty);
    expect(controller.suggestionFor(sessionId), isNull);
  });

  test('arrow right dismisses the suggestion instead of accepting it', () {
    final controller = TerminalSuggestionController();

    controller.handleInput(sessionId, 'fo');
    controller.setRemoteCompletions(sessionId, const [
      TerminalCompletionCandidate(
        replacement: 'folder',
        display: 'folder',
        description: 'directory',
        source: 'directory',
        kind: CompletionKind.directory,
      ),
    ]);
    expect(controller.completionSuffixFor(sessionId), 'lder');

    controller.handleInput(sessionId, '\x1b[C');

    expect(controller.suggestionFor(sessionId), isNull);
    expect(controller.acceptSuggestion(sessionId), isNull);
  });

  test('disabled controller never consumes keys', () {
    final controller = TerminalSuggestionController()..setEnabled(false);

    expect(controller.handleInput(sessionId, 'git st'), isFalse);
    expect(controller.inputFor(sessionId), isEmpty);
    expect(controller.moveSelection(sessionId, 1), isFalse);
    expect(controller.acceptSuggestion(sessionId), isNull);
  });

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
