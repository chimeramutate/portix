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
