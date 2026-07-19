import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/connection_manager/session_models.dart' as session_models;
import 'package:portix/src/features/ssh_sessions/widget/remote/terminal_workspace_view.dart';

class _TabDropCall {
  const _TabDropCall({required this.targetSessionId, required this.draggedSessionId});

  final String targetSessionId;
  final String draggedSessionId;
}

class _TabDragHarness extends StatefulWidget {
  const _TabDragHarness({required this.activeSessionId, super.key});

  final String activeSessionId;

  @override
  State<_TabDragHarness> createState() => _TabDragHarnessState();
}

class _TabDragHarnessState extends State<_TabDragHarness> {
  final calls = <_TabDropCall>[];

  @override
  Widget build(BuildContext context) {
    const sessions = [
      ('session-1', 'Mantap-68'),
      ('session-2', 'Mantap-68 2'),
      ('session-3', 'Mantap-69'),
    ];

    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final session in sessions) ...[
                DragTarget<String>(
                  onWillAcceptWithDetails: (details) => details.data != session.$1,
                  onAcceptWithDetails: (details) {
                    setState(() {
                      calls.add(
                        _TabDropCall(
                          targetSessionId: session.$1,
                          draggedSessionId: details.data,
                        ),
                      );
                    });
                  },
                  builder: (context, candidates, rejected) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: TerminalSessionTab(
                        sessionId: session.$1,
                        label: session.$2,
                        status: session_models.ConnectionStatus.connected,
                        active: widget.activeSessionId == session.$1,
                        onTap: () {},
                        onClose: () {},
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _dragTabOntoTab(
  WidgetTester tester, {
  required String draggedSessionId,
  required String targetSessionId,
}) async {
  final draggedTab = find.byKey(ValueKey('terminal-session-tab-$draggedSessionId'));
  final targetTab = find.byKey(ValueKey('terminal-session-tab-$targetSessionId'));

  expect(draggedTab, findsOneWidget);
  expect(targetTab, findsOneWidget);

  final start = tester.getCenter(draggedTab);
  final end = tester.getCenter(targetTab);

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
  group('Terminal session tab drag-and-drop', () {
    testWidgets('dragging active tab onto another tab uses that tab as explicit target', (
      tester,
    ) async {
      final harnessKey = GlobalKey<_TabDragHarnessState>();

      await tester.pumpWidget(
        _TabDragHarness(key: harnessKey, activeSessionId: 'session-2'),
      );
      await tester.pumpAndSettle();

      await _dragTabOntoTab(
        tester,
        draggedSessionId: 'session-2',
        targetSessionId: 'session-3',
      );

      final calls = harnessKey.currentState!.calls;
      expect(calls, isNotEmpty);
      expect(calls.last.targetSessionId, 'session-3');
      expect(calls.last.draggedSessionId, 'session-2');
    });

    testWidgets('dragging inactive tab onto active tab keeps active tab as explicit target', (
      tester,
    ) async {
      final harnessKey = GlobalKey<_TabDragHarnessState>();

      await tester.pumpWidget(
        _TabDragHarness(key: harnessKey, activeSessionId: 'session-2'),
      );
      await tester.pumpAndSettle();

      await _dragTabOntoTab(
        tester,
        draggedSessionId: 'session-3',
        targetSessionId: 'session-2',
      );

      final calls = harnessKey.currentState!.calls;
      expect(calls, isNotEmpty);
      expect(calls.last.targetSessionId, 'session-2');
      expect(calls.last.draggedSessionId, 'session-3');
    });
  });
}
