import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/connection_manager/session_models.dart';
import 'package:portix/src/features/ssh_sessions/controller/terminal_suggestion_controller.dart';
import 'package:portix/src/features/ssh_sessions/widget/remote/terminal_settings.dart';
import 'package:portix/src/features/ssh_sessions/widget/remote/terminal_shortcuts.dart';

void main() {
  const sessionId = 'ssh-session';

  test('allows Enter to accept history suggestions', () {
    final controller = TerminalSuggestionController();

    controller.handleInput(sessionId, 'git status');
    controller.handleInput(sessionId, '\r');
    controller.handleInput(sessionId, 'gi');

    expect(controller.canAcceptSuggestionWithEnter(sessionId), isTrue);
    expect(
      controller.suggestionFor(sessionId)?.source,
      TerminalSuggestionSource.history,
    );
  });

  test('does not allow Enter to accept remote completion suggestions', () {
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

    expect(controller.candidatesFor(sessionId), isNotEmpty);
    expect(
      controller.suggestionFor(sessionId)?.source,
      TerminalSuggestionSource.remoteHelp,
    );
    expect(controller.canAcceptSuggestionWithEnter(sessionId), isFalse);
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

  test('builds configurable terminal shortcuts', () {
    final shortcuts = terminalShortcutsFor(
      copyShortcut: TerminalClipboardShortcut.shiftCtrl,
      pasteShortcut: TerminalClipboardShortcut.ctrl,
    );

    expect(shortcuts.length, 3);
    expect(
      shortcuts.values.any((intent) => intent is SelectAllTextIntent),
      isTrue,
    );
    expect(
      shortcuts.values.any((intent) => intent is CopySelectionTextIntent),
      isTrue,
    );
    expect(shortcuts.values.any((intent) => intent is PasteTextIntent), isTrue);
  });

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
