import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/connection_manager/session_models.dart' as session_models;
import 'package:portix/src/features/ssh_sessions/controller/terminal_session_order_controller.dart';
import 'package:portix/src/features/ssh_sessions/controller/terminal_split_controller.dart';

void main() {
  const splitController = TerminalSplitController();

  group('split target selection', () {
    test('dragging active tab into workspace drop area keeps explicit target', () {
      const orderedIds = ['session-1', 'session-2', 'session-3'];

      final target = splitController.resolveSplitTargetForDrag(
        draggedSessionId: 'session-2',
        fallbackTargetSessionId: 'session-3',
        orderedSessionIds: orderedIds,
        workspaceSessionIds: const <String>{},
        existingSessionIds: orderedIds.toSet(),
      );

      expect(
        target,
        'session-3',
        reason: 'active tab dropped onto an explicit pane target must merge with that target',
      );
    });

    test('dragging non-active tab onto active tab keeps active tab as target', () {
      const orderedIds = ['session-1', 'session-2', 'session-3'];

      final target = splitController.resolveSplitTargetForDrag(
        draggedSessionId: 'session-3',
        fallbackTargetSessionId: 'session-2',
        orderedSessionIds: orderedIds,
        workspaceSessionIds: const <String>{},
        existingSessionIds: orderedIds.toSet(),
      );

      expect(
        target,
        'session-2',
        reason: 'dropping an inactive tab onto the active tab should create a workspace with the active tab, not the left neighbour',
      );
    });

    test('without explicit target the dragged tab falls back to left neighbour', () {
      const orderedIds = ['session-1', 'session-2', 'session-3'];

      final target = splitController.resolveSplitTargetForDrag(
        draggedSessionId: 'session-3',
        fallbackTargetSessionId: 'session-3',
        orderedSessionIds: orderedIds,
        workspaceSessionIds: const <String>{},
        existingSessionIds: orderedIds.toSet(),
      );

      expect(target, 'session-2');
    });

    test('first standalone tab falls back to right neighbour when needed', () {
      const orderedIds = ['session-1', 'session-2', 'session-3'];

      final target = splitController.resolveSplitTargetForDrag(
        draggedSessionId: 'session-1',
        fallbackTargetSessionId: 'session-1',
        orderedSessionIds: orderedIds,
        workspaceSessionIds: const <String>{},
        existingSessionIds: orderedIds.toSet(),
      );

      expect(target, 'session-2');
    });

    test('order controller preserves the intended neighbour relationship', () {
      final order = TerminalSessionOrderController();
      final sessions = [
        session_models.TerminalSession(
          id: 'session-1',
          profileId: 'p1',
          title: 'Tab 1',
          status: session_models.ConnectionStatus.connected,
          kind: session_models.SessionKind.ssh,
        ),
        session_models.TerminalSession(
          id: 'session-2',
          profileId: 'p2',
          title: 'Tab 2',
          status: session_models.ConnectionStatus.connected,
          kind: session_models.SessionKind.ssh,
        ),
        session_models.TerminalSession(
          id: 'session-3',
          profileId: 'p3',
          title: 'Tab 3',
          status: session_models.ConnectionStatus.connected,
          kind: session_models.SessionKind.ssh,
        ),
      ];

      final ordered = order.ordered(sessions, (session) => session.id);
      expect(ordered.map((session) => session.id).toList(), ['session-1', 'session-2', 'session-3']);

      final target = splitController.resolveSplitTargetForDrag(
        draggedSessionId: 'session-3',
        fallbackTargetSessionId: 'session-2',
        orderedSessionIds: ordered.map((session) => session.id).toList(),
        workspaceSessionIds: const <String>{},
        existingSessionIds: ordered.map((session) => session.id).toSet(),
      );

      expect(target, 'session-2');
    });
  });
}
