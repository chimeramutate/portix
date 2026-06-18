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
    required this.suggestionForSession,
    required this.suggestionCandidatesForSession,
    required this.suggestionSuffixForSession,
    required this.idleTerminal,
    required this.controllerForSession,
    required this.scrollControllerForSession,
    required this.focusNodeForSession,
    required this.viewKeyForSession,
    required this.idleController,
    required this.idleScrollController,
    required this.idleFocusNode,
    required this.idleViewKey,
    required this.keyboardEnabled,
    required this.copyShortcut,
    required this.pasteShortcut,
    required this.onFocus,
    required this.onClosePane,
    required this.onSplit,
    required this.onResizeBranch,
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
  final TerminalSuggestion? Function(String sessionId) suggestionForSession;
  final List<TerminalSuggestion> Function(String sessionId)
  suggestionCandidatesForSession;
  final String? Function(String sessionId) suggestionSuffixForSession;
  final Terminal idleTerminal;
  final TerminalController Function(String sessionId) controllerForSession;
  final ScrollController Function(String sessionId) scrollControllerForSession;
  final FocusNode Function(String sessionId) focusNodeForSession;
  final GlobalKey<TerminalViewState> Function(String sessionId)
  viewKeyForSession;
  final TerminalController idleController;
  final ScrollController idleScrollController;
  final FocusNode idleFocusNode;
  final GlobalKey<TerminalViewState> idleViewKey;
  final bool keyboardEnabled;
  final TerminalClipboardShortcut copyShortcut;
  final TerminalClipboardShortcut pasteShortcut;
  final ValueChanged<String> onFocus;
  final ValueChanged<String> onClosePane;
  final void Function(
    String targetSessionId,
    String draggedSessionId,
    SplitDirection direction,
  )
  onSplit;
  final void Function(SplitBranch target, SplitBranch replacement)
  onResizeBranch;
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
        scrollController: idleScrollController,
        focusNode: idleFocusNode,
        terminalViewKey: idleViewKey,
        keyboardEnabled: keyboardEnabled,
        copyShortcut: copyShortcut,
        pasteShortcut: pasteShortcut,
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
        suggestionForSession: suggestionForSession,
        suggestionCandidatesForSession: suggestionCandidatesForSession,
        suggestionSuffixForSession: suggestionSuffixForSession,
        controllerForSession: controllerForSession,
        scrollControllerForSession: scrollControllerForSession,
        focusNodeForSession: focusNodeForSession,
        viewKeyForSession: viewKeyForSession,
        keyboardEnabled: keyboardEnabled,
        copyShortcut: copyShortcut,
        pasteShortcut: pasteShortcut,
        onFocus: onFocus,
        onClosePane: onClosePane,
        onSplit: onSplit,
        onResizeBranch: onResizeBranch,
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
    required this.suggestionForSession,
    required this.suggestionCandidatesForSession,
    required this.suggestionSuffixForSession,
    required this.controllerForSession,
    required this.scrollControllerForSession,
    required this.focusNodeForSession,
    required this.viewKeyForSession,
    required this.keyboardEnabled,
    required this.copyShortcut,
    required this.pasteShortcut,
    required this.onFocus,
    required this.onClosePane,
    required this.onSplit,
    required this.onResizeBranch,
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
  final TerminalSuggestion? Function(String sessionId) suggestionForSession;
  final List<TerminalSuggestion> Function(String sessionId)
  suggestionCandidatesForSession;
  final String? Function(String sessionId) suggestionSuffixForSession;
  final TerminalController Function(String sessionId) controllerForSession;
  final ScrollController Function(String sessionId) scrollControllerForSession;
  final FocusNode Function(String sessionId) focusNodeForSession;
  final GlobalKey<TerminalViewState> Function(String sessionId)
  viewKeyForSession;
  final bool keyboardEnabled;
  final TerminalClipboardShortcut copyShortcut;
  final TerminalClipboardShortcut pasteShortcut;
  final ValueChanged<String> onFocus;
  final ValueChanged<String> onClosePane;
  final void Function(
    String targetSessionId,
    String draggedSessionId,
    SplitDirection direction,
  )
  onSplit;
  final void Function(SplitBranch target, SplitBranch replacement)
  onResizeBranch;
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
        scrollController: scrollControllerForSession(node.sessionId),
        focusNode: focusNode,
        terminalViewKey: viewKeyForSession(node.sessionId),
        status: statusForSession(node.sessionId),
        profile: profileForSession(node.sessionId),
        suggestion: node.sessionId == activeSessionId
            ? suggestionForSession(node.sessionId)
            : null,
        suggestionCandidates: node.sessionId == activeSessionId
            ? suggestionCandidatesForSession(node.sessionId)
            : const [],
        suggestionSuffix: node.sessionId == activeSessionId
            ? suggestionSuffixForSession(node.sessionId)
            : null,
        broadcastTyping: broadcastTyping,
        solo: soloSessionId == node.sessionId,
        active: node.sessionId == activeSessionId,
        keyboardEnabled: keyboardEnabled,
        copyShortcut: copyShortcut,
        pasteShortcut: pasteShortcut,
        allowPaneDrag: showPaneControls,
        onTap: () {
          onFocus(node.sessionId);
          if (keyboardEnabled) focusNode.requestFocus();
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
    final weights = branch.normalizedWeights;
    final children = [
      for (final child in branch.children)
        Flexible(
          flex: (weights[branch.children.indexOf(child)] * 1000).round(),
          child: SplitTreeView(
            node: child,
            activeSessionId: activeSessionId,
            soloSessionId: soloSessionId,
            broadcastTyping: broadcastTyping,
            showPaneControls: showPaneControls,
            terminalForSession: terminalForSession,
            statusForSession: statusForSession,
            profileForSession: profileForSession,
            suggestionForSession: suggestionForSession,
            suggestionCandidatesForSession: suggestionCandidatesForSession,
            suggestionSuffixForSession: suggestionSuffixForSession,
            controllerForSession: controllerForSession,
            scrollControllerForSession: scrollControllerForSession,
            focusNodeForSession: focusNodeForSession,
            viewKeyForSession: viewKeyForSession,
            keyboardEnabled: keyboardEnabled,
            copyShortcut: copyShortcut,
            pasteShortcut: pasteShortcut,
            onFocus: onFocus,
            onClosePane: onClosePane,
            onSplit: onSplit,
            onResizeBranch: onResizeBranch,
            onReconnect: onReconnect,
            onToggleBroadcast: onToggleBroadcast,
            onToggleSolo: onToggleSolo,
            canClosePane: canClosePane,
          ),
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = branch.axis == Axis.horizontal
            ? constraints.maxWidth
            : constraints.maxHeight;
        final totalWeight = weights.fold<double>(0, (sum, item) => sum + item);
        return Flex(
          direction: branch.axis,
          children: [
            for (var index = 0; index < children.length; index += 1) ...[
              if (index > 0)
                SplitResizeHandle(
                  axis: branch.axis,
                  onDragDelta: (delta) {
                    if (!available.isFinite || available <= 0) return;
                    final sign = branch.axis == Axis.horizontal ? 1.0 : 1.0;
                    final weightDelta = delta / available * totalWeight * sign;
                    onResizeBranch(
                      branch,
                      branch.withAdjustedDivider(index - 1, weightDelta),
                    );
                  },
                ),
              children[index],
            ],
          ],
        );
      },
    );
  }
}

class SplitResizeHandle extends StatelessWidget {
  const SplitResizeHandle({required this.axis, required this.onDragDelta});

  final Axis axis;
  final ValueChanged<double> onDragDelta;

  @override
  Widget build(BuildContext context) {
    final horizontal = axis == Axis.horizontal;
    return MouseRegion(
      cursor: horizontal
          ? SystemMouseCursors.resizeColumn
          : SystemMouseCursors.resizeRow,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: horizontal
            ? (details) => onDragDelta(details.delta.dx)
            : null,
        onVerticalDragUpdate: horizontal
            ? null
            : (details) => onDragDelta(details.delta.dy),
        child: SizedBox(
          width: horizontal ? 12 : double.infinity,
          height: horizontal ? double.infinity : 12,
          child: Center(
            child: Container(
              width: horizontal ? 8 : 42,
              height: horizontal ? 42 : 8,
              decoration: BoxDecoration(
                color: AppColors.surfaceCard.withValues(alpha: .86),
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: AppColors.border),
              ),
              child: Icon(
                horizontal ? Icons.swap_horiz_rounded : Icons.swap_vert_rounded,
                size: 14,
                color: AppColors.cyan,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
