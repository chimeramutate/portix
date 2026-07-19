import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/connection_manager/session_models.dart' as session_models;
import 'package:portix/src/features/ssh_sessions/controller/terminal_split_controller.dart';
import 'package:portix/src/features/ssh_sessions/widget/remote/terminal_shortcuts.dart';
import 'package:portix/src/features/ssh_sessions/widget/remote/terminal_workspace_view.dart';
import 'package:xterm/xterm.dart';

class _SplitCall {
  const _SplitCall({
    required this.targetSessionId,
    required this.draggedSessionId,
    required this.direction,
  });

  final String targetSessionId;
  final String draggedSessionId;
  final SplitDirection direction;
}

Future<void> _pumpWorkspaceView(
  WidgetTester tester, {
  required SplitNode root,
  required String activeSessionId,
  required void Function(
    String targetSessionId,
    String draggedSessionId,
    SplitDirection direction,
  )
  onSplit,
}) async {
  final terminals = {
    for (final sessionId in root.sessionIds) sessionId: Terminal(maxLines: 200),
  };
  final controllers = {
    for (final sessionId in root.sessionIds) sessionId: TerminalController(),
  };
  final scrollControllers = {
    for (final sessionId in root.sessionIds) sessionId: ScrollController(),
  };
  final focusNodes = {
    for (final sessionId in root.sessionIds) sessionId: FocusNode(),
  };
  final viewKeys = {
    for (final sessionId in root.sessionIds)
      sessionId: GlobalKey<TerminalViewState>(),
  };

  for (final entry in terminals.entries) {
    entry.value.write('terminal ${entry.key}\r\nready');
  }

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 1200,
          height: 700,
          child: TerminalWorkspaceView(
            root: root,
            activeSessionId: activeSessionId,
            soloSessionId: null,
            broadcastTyping: false,
            showPaneControls: true,
            terminalForSession: (sessionId) => terminals[sessionId]!,
            statusForSession: (_) => session_models.ConnectionStatus.connected,
            profileForSession: (_) => null,
            suggestionForSession: (_) => null,
            suggestionCandidatesForSession: (_) => const [],
            suggestionSuffixForSession: (_) => null,
            idleTerminal: Terminal(),
            controllerForSession: (sessionId) => controllers[sessionId]!,
            scrollControllerForSession: (sessionId) => scrollControllers[sessionId]!,
            focusNodeForSession: (sessionId) => focusNodes[sessionId]!,
            viewKeyForSession: (sessionId) => viewKeys[sessionId]!,
            idleController: TerminalController(),
            idleScrollController: ScrollController(),
            idleFocusNode: FocusNode(),
            idleViewKey: GlobalKey<TerminalViewState>(),
            keyboardEnabled: true,
            copyShortcut: TerminalClipboardShortcut.shiftCtrl,
            pasteShortcut: TerminalClipboardShortcut.ctrl,
            textColor: Colors.white,
            backgroundColor: Colors.black,
            fontFamily: 'monospace',
            fontSize: 13,
            onFocus: (_) {},
            onClosePane: (_) {},
            onSplit: onSplit,
            onResizeBranch: (_, __) {},
            onReconnect: (_) {},
            onToggleBroadcast: () {},
            onToggleSolo: (_) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _dragHandleForPane(String sessionId) {
  final paneFinder = find.byWidgetPredicate(
    (widget) => widget is TerminalPane && widget.sessionId == sessionId,
  );
  expect(paneFinder, findsOneWidget);
  return find.descendant(
    of: paneFinder,
    matching: find.byTooltip('Drag terminal pane'),
  );
}

Future<void> _dragHandleToPaneDropZone(
  WidgetTester tester, {
  required String draggedSessionId,
  required String targetSessionId,
  required SplitDirection direction,
}) async {
  final dragHandle = _dragHandleForPane(draggedSessionId);
  expect(dragHandle, findsOneWidget);

  final targetPane = find.byWidgetPredicate(
    (widget) => widget is TerminalPane && widget.sessionId == targetSessionId,
  );
  expect(targetPane, findsOneWidget);

  final paneRect = tester.getRect(targetPane);
  final end = switch (direction) {
    SplitDirection.left => Offset(paneRect.left + 24, paneRect.center.dy),
    SplitDirection.right => Offset(paneRect.right - 24, paneRect.center.dy),
    SplitDirection.top => Offset(paneRect.center.dx, paneRect.top + 24),
    SplitDirection.bottom => Offset(paneRect.center.dx, paneRect.bottom - 24),
  };
  final start = tester.getCenter(dragHandle);

  final gesture = await tester.startGesture(start, kind: PointerDeviceKind.mouse);
  await tester.pump();
  await gesture.moveTo(Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2));
  await tester.pump();
  await gesture.moveTo(end);
  await tester.pump();
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  group('TerminalWorkspaceView drag-and-drop', () {
    testWidgets('dragging active pane into another pane targets that pane', (
      tester,
    ) async {
      final calls = <_SplitCall>[];

      await _pumpWorkspaceView(
        tester,
        root: const SplitBranch(
          Axis.horizontal,
          [SplitLeaf('session-2'), SplitLeaf('session-3')],
          weights: [1, 1],
        ),
        activeSessionId: 'session-2',
        onSplit: (targetSessionId, draggedSessionId, direction) {
          calls.add(
            _SplitCall(
              targetSessionId: targetSessionId,
              draggedSessionId: draggedSessionId,
              direction: direction,
            ),
          );
        },
      );

      await _dragHandleToPaneDropZone(
        tester,
        draggedSessionId: 'session-2',
        targetSessionId: 'session-3',
        direction: SplitDirection.left,
      );

      expect(calls, isNotEmpty);
      expect(calls.last.targetSessionId, 'session-3');
      expect(calls.last.draggedSessionId, 'session-2');
    });

    testWidgets('dragging inactive pane onto active pane keeps active pane as target', (
      tester,
    ) async {
      final calls = <_SplitCall>[];

      await _pumpWorkspaceView(
        tester,
        root: const SplitBranch(
          Axis.horizontal,
          [SplitLeaf('session-2'), SplitLeaf('session-3')],
          weights: [1, 1],
        ),
        activeSessionId: 'session-2',
        onSplit: (targetSessionId, draggedSessionId, direction) {
          calls.add(
            _SplitCall(
              targetSessionId: targetSessionId,
              draggedSessionId: draggedSessionId,
              direction: direction,
            ),
          );
        },
      );

      await _dragHandleToPaneDropZone(
        tester,
        draggedSessionId: 'session-3',
        targetSessionId: 'session-2',
        direction: SplitDirection.right,
      );

      expect(calls, isNotEmpty);
      expect(calls.last.targetSessionId, 'session-2');
      expect(calls.last.draggedSessionId, 'session-3');
    });
  });
}
