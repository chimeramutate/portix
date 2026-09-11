import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/connection_manager/session_models.dart'
    as session_models;
import 'package:portix/src/features/ssh_sessions/widget/remote/terminal_workspace_view.dart';
import 'package:xterm/xterm.dart';

Future<void> _pumpTerminalPane(
  WidgetTester tester, {
  required Terminal terminal,
  required TerminalController controller,
  required ScrollController scrollController,
  required FocusNode focusNode,
  required GlobalKey<TerminalViewState> viewKey,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 980,
            height: 560,
            child: TerminalPane(
              terminal: terminal,
              controller: controller,
              scrollController: scrollController,
              focusNode: focusNode,
              terminalViewKey: viewKey,
              sessionId: 'session-1',
              status: session_models.ConnectionStatus.connected,
              active: true,
              keyboardEnabled: true,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('Terminal scrolling with long output', () {
    testWidgets('scrollback exposes a scrollable extent after long output', (
      tester,
    ) async {
      final terminal = Terminal(maxLines: 5000);
      final controller = TerminalController();
      final scrollController = ScrollController();
      final focusNode = FocusNode();
      final viewKey = GlobalKey<TerminalViewState>();

      await _pumpTerminalPane(
        tester,
        terminal: terminal,
        controller: controller,
        scrollController: scrollController,
        focusNode: focusNode,
        viewKey: viewKey,
      );

      // Simulate a long log (e.g. `cat app.log`).
      terminal.write(
        List.generate(
          400,
          (i) => '[2026-06-21 23:15:20,5${(i % 10).toString()}] [ INFO] '
              'log line number $i - padding padding padding padding padding',
        ).join('\r\n'),
      );
      terminal.write('\r\nuser@host:~\$ ');
      await tester.pumpAndSettle();

      final position = scrollController.position;
      expect(terminal.buffer.lines.length, greaterThan(300));
      expect(position.maxScrollExtent, greaterThan(0),
          reason: 'Long output should make the terminal scrollable');

      // At rest the terminal should be scrolled to the bottom (stick to bottom).
      expect(
        position.pixels,
        closeTo(position.maxScrollExtent, 1),
        reason: 'Terminal should autoscroll to bottom after new output',
      );

      focusNode.dispose();
      scrollController.dispose();
    });
testWidgets('mouse wheel scrolls up and down through the scrollback', (
      tester,
    ) async {
      final terminal = Terminal(maxLines: 5000);
      final controller = TerminalController();
      final scrollController = ScrollController();
      final focusNode = FocusNode();
      final viewKey = GlobalKey<TerminalViewState>();

      await _pumpTerminalPane(
        tester,
        terminal: terminal,
        controller: controller,
        scrollController: scrollController,
        focusNode: focusNode,
        viewKey: viewKey,
      );

      terminal.write(
        List.generate(
          400,
          (i) => '[2026-06-21 23:15:20,5${(i % 10).toString()}] [ INFO] '
              'log line number $i - padding padding padding padding padding',
        ).join('\r\n'),
      );
      terminal.write('\r\nuser@host:~\$ ');
      await tester.pumpAndSettle();

      final position = scrollController.position;
      final bottom = position.maxScrollExtent;
      expect(bottom, greaterThan(0));

      final terminalFinder = find.byType(TerminalView);
      final center = tester.getCenter(terminalFinder);

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: center);
      await tester.pump();

      for (var i = 0; i < 10; i++) {
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: center,
            scrollDelta: Offset(0, -120),
          ),
        );
        await tester.pump();
      }

      expect(
        scrollController.position.pixels,
        lessThan(bottom),
        reason: 'Wheel up should scroll toward the top of the scrollback',
      );

      for (var i = 0; i < 20; i++) {
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: center,
            scrollDelta: Offset(0, 120),
          ),
        );
        await tester.pump();
      }

      expect(
        scrollController.position.pixels,
        closeTo(scrollController.position.maxScrollExtent, 1),
        reason: 'Wheel down should return to the bottom',
      );

      await gesture.removePointer();
      focusNode.dispose();
      scrollController.dispose();
    });

testWidgets('streamed chunks keep the terminal pinned to the bottom', (
      tester,
    ) async {
      final terminal = Terminal(maxLines: 5000);
      final controller = TerminalController();
      final scrollController = ScrollController();
      final focusNode = FocusNode();
      final viewKey = GlobalKey<TerminalViewState>();

      await _pumpTerminalPane(
        tester,
        terminal: terminal,
        controller: controller,
        scrollController: scrollController,
        focusNode: focusNode,
        viewKey: viewKey,
      );

      // Simulate a real SSH session: output arrives in small chunks over time.
      const line = '[ INFO] streamed log line padding padding padding padding';
      for (var i = 0; i < 50; i++) {
        terminal.write('\r\n$line $i\r\n');
        await tester.pumpAndSettle();
      }

      final position = scrollController.position;
      expect(position.maxScrollExtent, greaterThan(0.0));
      expect(
        position.pixels,
        closeTo(position.maxScrollExtent, 1.0),
        reason: 'While idle at the bottom, streamed output should keep the '
            'terminal pinned to the bottom so the prompt stays visible.',
      );

      focusNode.dispose();
      scrollController.dispose();
    });

    testWidgets('user scrolled up is not yanked back down while reading', (
      tester,
    ) async {
      final terminal = Terminal(maxLines: 5000);
      final controller = TerminalController();
      final scrollController = ScrollController();
      final focusNode = FocusNode();
      final viewKey = GlobalKey<TerminalViewState>();

      await _pumpTerminalPane(
        tester,
        terminal: terminal,
        controller: controller,
        scrollController: scrollController,
        focusNode: focusNode,
        viewKey: viewKey,
      );

      const line = '[ INFO] first burst line padding padding padding padding';
      terminal.write(List.generate(200, (i) => '$line $i').join('\r\n'));
      await tester.pumpAndSettle();
      expect(
        scrollController.position.pixels,
        closeTo(scrollController.position.maxScrollExtent, 1.0),
      );

      // User scrolls all the way up to read the beginning of the log.
      scrollController.jumpTo(0);
      await tester.pumpAndSettle();
      expect(scrollController.position.pixels, 0.0);

      // While the user is reading the top, a new chunk arrives. The viewport
      // must NOT be dragged back to the bottom.
      terminal.write('\r\n[ INFO] a brand new line while reading padding\r\n');
      await tester.pumpAndSettle();
      expect(
        scrollController.position.pixels,
        lessThan(scrollController.position.maxScrollExtent),
        reason: 'While scrolled up, new output must not yank the viewport '
            'to the bottom.',
      );

      focusNode.dispose();
      scrollController.dispose();
    });
  });
}