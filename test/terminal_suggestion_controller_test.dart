import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/connection_manager/session_models.dart';
import 'package:portix/src/features/ssh_sessions/controller/terminal_suggestion_controller.dart';

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
}
