import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/core/theme/app_theme.dart';
import 'package:portix/src/features/ssh_sessions/widget/remote/terminal_workspace_view.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    String? failure,
    bool connecting = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: appTheme,
        home: Scaffold(
          body: TerminalConnectionOverlay(
            profile: null,
            connecting: connecting,
            failure: failure,
            onReconnect: () {},
          ),
        ),
      ),
    );
  }

  testWidgets('the connection card says why the session went down', (
    tester,
  ) async {
    await pump(tester, failure: 'Connection lost. Host is unreachable.');
    expect(find.text('Connection lost. Host is unreachable.'), findsOneWidget);

    // Still the reason after the network check times out.
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(find.text('Connection lost. Host is unreachable.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('falls back to the generic line with no reason', (tester) async {
    await pump(tester);
    expect(
      find.text('This terminal session is not connected.'),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a retry in progress drops the old reason', (tester) async {
    await pump(tester, failure: 'Connection lost.', connecting: true);
    expect(find.text('Connection lost.'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
