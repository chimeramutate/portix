import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/connection_manager/session_models.dart' as session_models;
import 'package:portix/src/features/ssh_sessions/widget/remote/terminal_workspace_view.dart';
import 'package:xterm/xterm.dart';

Future<void> _pumpEofLikeTerminalPane(
  WidgetTester tester, {
  required Terminal terminal,
  required TerminalController controller,
  required ScrollController scrollController,
  required FocusNode focusNode,
  required GlobalKey<TerminalViewState> viewKey,
  bool centered = true,
  bool positionedFill = false,
  bool withOuterTapWrapper = false,
  bool withBottomRightOverlay = false,
}) async {
  Widget child = SizedBox(
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
  );

  if (centered) {
    child = Center(child: child);
  }

  if (withOuterTapWrapper) {
    child = GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {},
      child: child,
    );
  }

  if (positionedFill || withBottomRightOverlay) {
    child = Stack(
      children: [
        if (positionedFill) Positioned.fill(child: child) else child,
        if (withBottomRightOverlay)
          Positioned(
          right: 18,
          bottom: 18,
            child: IgnorePointer(
              child: Container(
                width: 320,
                height: 120,
                color: Colors.red.withValues(alpha: .2),
              ),
            ),
          ),
      ],
    );
  }

  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  await tester.pumpAndSettle();
}

Future<void> _dragFromUpperViewport(WidgetTester tester) async {
  final terminalFinder = find.byType(TerminalView);
  expect(terminalFinder, findsOneWidget);

  final renderBox = tester.renderObject<RenderBox>(terminalFinder);
  expect(renderBox.size.width, greaterThan(300));
  expect(renderBox.size.height, greaterThan(200));

  final topLeft = tester.getTopLeft(terminalFinder);
  final start = topLeft + const Offset(40, 24);
  final end = topLeft + const Offset(260, 96);

  expect(start.dx, greaterThan(topLeft.dx));
  expect(start.dy, greaterThan(topLeft.dy));
  expect(end.dx, lessThanOrEqualTo(topLeft.dx + renderBox.size.width));
  expect(end.dy, lessThanOrEqualTo(topLeft.dy + renderBox.size.height));

  final gesture = await tester.startGesture(
    start,
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump();

  await gesture.moveTo(end);
  await tester.pump();

  await gesture.up();
  await tester.pump();
}

void main() {
  group('TerminalPane integration', () {
    testWidgets('drag selection works from upper area in EOF-like alt buffer pane', (
      tester,
    ) async {
      final terminal = Terminal(maxLines: 200);
      final controller = TerminalController(
        pointerInputs: const PointerInputs.all(),
      );
      final scrollController = ScrollController();
      final focusNode = FocusNode();
      final viewKey = GlobalKey<TerminalViewState>();

      terminal.write('\x1b[?1049h');
      terminal.write('\x1b[2J\x1b[H');
      terminal.write(
        <String>[
          '[2026-06-21 23:15:20,528] [ INFO] row 18',
          '[2026-06-21 23:15:20,529] [ INFO] row 19',
          '[2026-06-21 23:15:20,530] [ INFO] row 20',
          '[2026-06-21 23:15:20,531] [ INFO] row 21',
          '[2026-06-21 23:15:20,532] [ INFO] row 22',
          '[2026-06-21 23:15:20,533] [ INFO] row 23',
          '(END)',
        ].join('\r\n'),
      );
      terminal.write('\x1b[?1000h');
      terminal.write('\x1b[?1002h');

      await _pumpEofLikeTerminalPane(
        tester,
        terminal: terminal,
        controller: controller,
        scrollController: scrollController,
        focusNode: focusNode,
        viewKey: viewKey,
      );

      await _dragFromUpperViewport(tester);

      final selection = controller.selection;
      expect(selection, isNotNull);
      expect(selection!.normalized.begin.y, lessThanOrEqualTo(2));
      expect(selection.normalized.end.y, greaterThanOrEqualTo(
        selection.normalized.begin.y,
      ));

      focusNode.dispose();
      scrollController.dispose();
    });

    testWidgets(
      'drag selection still works when centered only',
      (tester) async {
        final terminal = Terminal(maxLines: 200);
        final controller = TerminalController(
          pointerInputs: const PointerInputs.all(),
        );
        final scrollController = ScrollController();
        final focusNode = FocusNode();
        final viewKey = GlobalKey<TerminalViewState>();

        terminal.write('\x1b[?1049h');
        terminal.write('\x1b[2J\x1b[H');
        terminal.write(
          List<String>.generate(
            24,
            (index) => '[2026-06-21 23:15:20,5${index.toString().padLeft(2, '0')}] [ INFO] row $index',
          ).join('\r\n'),
        );
        terminal.write('\r\n(END)');
        terminal.write('\x1b[?1000h');
        terminal.write('\x1b[?1002h');

        await _pumpEofLikeTerminalPane(
          tester,
          terminal: terminal,
          controller: controller,
          scrollController: scrollController,
          focusNode: focusNode,
          viewKey: viewKey,
          centered: true,
        );

        await _dragFromUpperViewport(tester);

        final selection = controller.selection;
        expect(selection, isNotNull);
        expect(selection!.normalized.begin.y, lessThanOrEqualTo(2));
        expect(selection.normalized.end.y, greaterThan(selection.normalized.begin.y));

        focusNode.dispose();
        scrollController.dispose();
      },
    );

    testWidgets(
      'drag selection still works inside plain Stack without Positioned.fill',
      (tester) async {
        final terminal = Terminal(maxLines: 200);
        final controller = TerminalController(
          pointerInputs: const PointerInputs.all(),
        );
        final scrollController = ScrollController();
        final focusNode = FocusNode();
        final viewKey = GlobalKey<TerminalViewState>();

        terminal.write('\x1b[?1049h');
        terminal.write('\x1b[2J\x1b[H');
        terminal.write(
          List<String>.generate(
            24,
            (index) => '[2026-06-21 23:15:20,5${index.toString().padLeft(2, '0')}] [ INFO] row $index',
          ).join('\r\n'),
        );
        terminal.write('\r\n(END)');
        terminal.write('\x1b[?1000h');
        terminal.write('\x1b[?1002h');

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Stack(
                children: [
                  Center(
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
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await _dragFromUpperViewport(tester);

        final selection = controller.selection;
        expect(selection, isNotNull);
        expect(selection!.normalized.begin.y, lessThanOrEqualTo(2));
        expect(selection.normalized.end.y, greaterThan(selection.normalized.begin.y));

        focusNode.dispose();
        scrollController.dispose();
      },
    );

    testWidgets(
      'drag selection still works when using Positioned.fill only',
      (tester) async {
        final terminal = Terminal(maxLines: 200);
        final controller = TerminalController(
          pointerInputs: const PointerInputs.all(),
        );
        final scrollController = ScrollController();
        final focusNode = FocusNode();
        final viewKey = GlobalKey<TerminalViewState>();

        terminal.write('\x1b[?1049h');
        terminal.write('\x1b[2J\x1b[H');
        terminal.write(
          List<String>.generate(
            24,
            (index) => '[2026-06-21 23:15:20,5${index.toString().padLeft(2, '0')}] [ INFO] row $index',
          ).join('\r\n'),
        );
        terminal.write('\r\n(END)');
        terminal.write('\x1b[?1000h');
        terminal.write('\x1b[?1002h');

        await _pumpEofLikeTerminalPane(
          tester,
          terminal: terminal,
          controller: controller,
          scrollController: scrollController,
          focusNode: focusNode,
          viewKey: viewKey,
          centered: false,
          positionedFill: true,
        );

        await _dragFromUpperViewport(tester);

        final selection = controller.selection;
        expect(selection, isNotNull);
        expect(selection!.normalized.begin.y, lessThanOrEqualTo(2));
        expect(selection.normalized.end.y, greaterThan(selection.normalized.begin.y));

        focusNode.dispose();
        scrollController.dispose();
      },
    );
  });
}
