import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/features/ssh_sessions/widget/remote/terminal_workspace_view.dart';

void main() {
  testWidgets('right-click menu offers Rename', (tester) async {
    var renamed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: TerminalSessionTab(
              sessionId: 's1',
              label: 'web',
              onDuplicate: () {},
              onRename: () => renamed++,
            ),
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('terminal-session-tab-s1')),
      buttons: kSecondaryButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();

    expect(renamed, 1);
  });
}
