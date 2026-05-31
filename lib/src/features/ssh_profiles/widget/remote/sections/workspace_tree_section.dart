part of '../terminal_workspace_view.dart';

class TerminalWorkspaceView extends StatelessWidget {
  const TerminalWorkspaceView({
    required this.root,
    required this.activeSessionId,
    required this.soloSessionId,
    required this.broadcastTyping,
    required this.showPaneControls,
    required this.terminalForSession,
    required this.statusForSession,
    required this.profileForSession,
    required this.idleTerminal,
    required this.controllerForSession,
    required this.focusNodeForSession,
    required this.idleController,
    required this.idleFocusNode,
    required this.onFocus,
    required this.onClosePane,
    required this.onSplit,
    required this.onReconnect,
    required this.onToggleBroadcast,
    required this.onToggleSolo,
  });

  final SplitNode? root;
  final String? activeSessionId;
  final String? soloSessionId;
  final bool broadcastTyping;
  final bool showPaneControls;
  final Terminal Function(String sessionId) terminalForSession;
  final session_models.ConnectionStatus Function(String sessionId)
  statusForSession;
  final domain.SshProfile? Function(String sessionId) profileForSession;
  final Terminal idleTerminal;
  final TerminalController Function(String sessionId) controllerForSession;
  final FocusNode Function(String sessionId) focusNodeForSession;
  final TerminalController idleController;
  final FocusNode idleFocusNode;
  final ValueChanged<String> onFocus;
  final ValueChanged<String> onClosePane;
  final void Function(
    String targetSessionId,
    String draggedSessionId,
    SplitDirection direction,
  )
  onSplit;
  final ValueChanged<String> onReconnect;
  final VoidCallback onToggleBroadcast;
  final ValueChanged<String> onToggleSolo;

  @override
  Widget build(BuildContext context) {
    final root = this.root;
    if (root == null) {
      return TerminalPane(
        terminal: idleTerminal,
        controller: idleController,
        focusNode: idleFocusNode,
      );
    }
    return Padding(
      padding: const EdgeInsets.all(8),
      child: SplitTreeView(
        node: root,
        activeSessionId: activeSessionId,
        soloSessionId: soloSessionId,
        broadcastTyping: broadcastTyping,
        showPaneControls: showPaneControls,
        terminalForSession: terminalForSession,
        statusForSession: statusForSession,
        profileForSession: profileForSession,
        controllerForSession: controllerForSession,
        focusNodeForSession: focusNodeForSession,
        onFocus: onFocus,
        onClosePane: onClosePane,
        onSplit: onSplit,
        onReconnect: onReconnect,
        onToggleBroadcast: onToggleBroadcast,
        onToggleSolo: onToggleSolo,
        canClosePane: root.sessionIds.length > 1,
      ),
    );
  }
}

class SplitTreeView extends StatelessWidget {
  const SplitTreeView({
    required this.node,
    required this.activeSessionId,
    required this.soloSessionId,
    required this.broadcastTyping,
    required this.showPaneControls,
    required this.terminalForSession,
    required this.statusForSession,
    required this.profileForSession,
    required this.controllerForSession,
    required this.focusNodeForSession,
    required this.onFocus,
    required this.onClosePane,
    required this.onSplit,
    required this.onReconnect,
    required this.onToggleBroadcast,
    required this.onToggleSolo,
    required this.canClosePane,
  });

  final SplitNode node;
  final String? activeSessionId;
  final String? soloSessionId;
  final bool broadcastTyping;
  final bool showPaneControls;
  final Terminal Function(String sessionId) terminalForSession;
  final session_models.ConnectionStatus Function(String sessionId)
  statusForSession;
  final domain.SshProfile? Function(String sessionId) profileForSession;
  final TerminalController Function(String sessionId) controllerForSession;
  final FocusNode Function(String sessionId) focusNodeForSession;
  final ValueChanged<String> onFocus;
  final ValueChanged<String> onClosePane;
  final void Function(
    String targetSessionId,
    String draggedSessionId,
    SplitDirection direction,
  )
  onSplit;
  final ValueChanged<String> onReconnect;
  final VoidCallback onToggleBroadcast;
  final ValueChanged<String> onToggleSolo;
  final bool canClosePane;

  @override
  Widget build(BuildContext context) {
    final node = this.node;
    if (node is SplitLeaf) {
      final focusNode = focusNodeForSession(node.sessionId);
      return TerminalPane(
        sessionId: node.sessionId,
        terminal: terminalForSession(node.sessionId),
        controller: controllerForSession(node.sessionId),
        focusNode: focusNode,
        status: statusForSession(node.sessionId),
        profile: profileForSession(node.sessionId),
        broadcastTyping: broadcastTyping,
        solo: soloSessionId == node.sessionId,
        active: node.sessionId == activeSessionId,
        onTap: () {
          onFocus(node.sessionId);
          focusNode.requestFocus();
        },
        onReconnect: () => onReconnect(node.sessionId),
        onToggleBroadcast: showPaneControls ? onToggleBroadcast : null,
        onToggleSolo: showPaneControls
            ? () => onToggleSolo(node.sessionId)
            : null,
        onSplit: (draggedSessionId, direction) =>
            onSplit(node.sessionId, draggedSessionId, direction),
      );
    }

    final branch = node as SplitBranch;
    final children = [
      for (final child in branch.children)
        Expanded(
          child: SplitTreeView(
            node: child,
            activeSessionId: activeSessionId,
            soloSessionId: soloSessionId,
            broadcastTyping: broadcastTyping,
            showPaneControls: showPaneControls,
            terminalForSession: terminalForSession,
            statusForSession: statusForSession,
            profileForSession: profileForSession,
            controllerForSession: controllerForSession,
            focusNodeForSession: focusNodeForSession,
            onFocus: onFocus,
            onClosePane: onClosePane,
            onSplit: onSplit,
            onReconnect: onReconnect,
            onToggleBroadcast: onToggleBroadcast,
            onToggleSolo: onToggleSolo,
            canClosePane: canClosePane,
          ),
        ),
    ];

    return Flex(
      direction: branch.axis,
      children: [
        for (var index = 0; index < children.length; index += 1) ...[
          if (index > 0)
            SizedBox(
              width: branch.axis == Axis.horizontal ? 8 : 0,
              height: branch.axis == Axis.vertical ? 8 : 0,
            ),
          children[index],
        ],
      ],
    );
  }
}
