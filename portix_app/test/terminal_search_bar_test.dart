import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/features/ssh_sessions/controller/terminal_search_controller.dart';
import 'package:portix/src/features/ssh_sessions/widget/remote/terminal_search_bar.dart';
import 'package:portix/src/features/ssh_sessions/widget/remote/terminal_themes.dart';
import 'package:xterm/xterm.dart';

void main() {
  testWidgets('typing searches, Enter and Shift+Enter step, Esc closes', (
    tester,
  ) async {
    final search = TerminalSearchController(
      terminal: Terminal()..write('deploy ok\r\ndeploy failed\r\ndone'),
      controller: TerminalController(),
      theme: portixBuiltinTheme,
      reveal: (_) {},
    );
    addTearDown(search.dispose);
    var closed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TerminalSearchBar(search: search, onClose: () => closed = true),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'DEPLOY');
    await tester.pump();
    expect(find.text('2/2'), findsOneWidget);

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(find.text('1/2'), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.pump();
    expect(find.text('2/2'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'nothing');
    await tester.pump();
    expect(find.text('No results'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(closed, isTrue);
  });
}
