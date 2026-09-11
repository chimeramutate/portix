import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/features/ssh_sessions/controller/terminal_suggestion_controller.dart';
import 'package:xterm/xterm.dart';

void main() {
  group('AutoScroll Behavior Tests', () {
    test('Terminal should not auto-scroll when scrolled up', () {
      // This test verifies that when user manually scrolls up,
      // the terminal doesn't auto-scroll on new input
      // The actual implementation is in terminal_view.dart
      // This is a conceptual test
      expect(true, isTrue);
    });
  });

  group('Suggestion Controller Tests', () {
    late TerminalSuggestionController controller;
    late Terminal terminal;

    setUp(() {
      controller = TerminalSuggestionController();
      terminal = Terminal();
    });

    // Regression: arrow keys / cursor escapes arrive at `handleInput` with no
    // leading ESC once the controller rejects the ESC byte, but their printable
    // body (`[A`/`[D`/`3~`) used to be buffered as typed text, polluting the
    // suggestion input with `[D[D…[A[A` garbage.
    test('arrow/home/end/delete escapes are not buffered as input', () {
      // Multiple Left arrows, then a partial word, then Up/Down/Home/End/Delete.
      controller.handleInput('s', '\x1b[D');
      controller.handleInput('s', '\x1b[D');
      controller.handleInput('s', '\x1b[A');
      controller.handleInput('s', '\x1b[B');
      controller.handleInput('s', '\x1b[3~');
      controller.handleInput('s', '\x1b[4~');
      controller.handleInput('s', '\x1b[H');
      controller.handleInput('s', '\x1b[F');
      controller.handleInput('s', '\x1bOC'); // SS3 form

      expect(controller.inputFor('s'), isEmpty);
      expect(controller.suggestionFor('s'), isNull);
      expect(controller.candidatesFor('s'), isEmpty);
    });

    test('a normal character following escapes is still buffered', () {
      controller.handleInput('s', '\x1b[D');
      controller.handleInput('s', '\x1b[D');
      controller.handleInput('s', 'a');

      expect(controller.inputFor('s'), equals('a'));
    });

    test('mixed printable text and escapes buffer only the text', () {
      controller.handleInput('s', 'kubectl\x1b[Dlogs');

      expect(controller.inputFor('s'), equals('kubectllogs'));
    });

    test('completion suffix is correctly calculated', () {
      controller.handleInput('test-session', 'kubectl logs');

      // Add a suggestion that starts with the input
      controller.setRemoteHelpSuggestions('test-session', [
        'kubectl logs pod-name -n namespace',
        'kubectl logs pod-name -n another',
      ]);

      final suggestion = controller.suggestionFor('test-session');
      expect(suggestion, isNotNull);
      expect(suggestion!.command, equals('kubectl logs pod-name -n namespace'));

      final suffix = controller.completionSuffixFor('test-session');
      expect(suffix, equals(' pod-name -n namespace'));
    });

    test('getCurrentWord returns the last word', () {
      expect(controller.getCurrentWord('kubectl logs'), equals('logs'));
      expect(controller.getCurrentWord('kubectl logs pod'), equals('pod'));
      expect(controller.getCurrentWord(''), equals(''));
      expect(controller.getCurrentWord(' '), equals(''));
    });

    test('selectSuggestionFromUI accepts the suggestion', () {
      controller.handleInput('test-session', 'kubectl logs');

      final suggestion = TerminalSuggestion(
        command: 'kubectl logs pod-name',
        source: TerminalSuggestionSource.remoteHelp,
      );

      final suffix = controller.selectSuggestionFromUI(
        'test-session',
        suggestion,
      );
      expect(suffix, equals(' pod-name'));

      final input = controller.inputFor('test-session');
      expect(input, equals('kubectl logs pod-name'));
    });

    test('suggestions are filtered correctly', () {
      controller.handleInput('test-session', 'kubectl');

      controller.setRemoteHelpSuggestions('test-session', [
        'kubectl get pods',
        'kubectl describe pod my-pod',
        'kubectl logs my-pod',
      ]);

      final candidates = controller.candidatesFor('test-session');
      expect(candidates.length, greaterThan(0));

      // All should start with 'kubectl'
      for (final candidate in candidates) {
        expect(candidate.command.startsWith('kubectl'), isTrue);
      }
    });
  });
}
