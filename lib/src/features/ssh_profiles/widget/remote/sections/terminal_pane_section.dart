part of '../terminal_workspace_view.dart';

class TerminalPane extends StatelessWidget {
  const TerminalPane({
    required this.terminal,
    required this.controller,
    required this.focusNode,
    this.sessionId,
    this.status = session_models.ConnectionStatus.connected,
    this.profile,
    this.broadcastTyping = false,
    this.solo = false,
    this.active = false,
    this.onTap,
    this.onReconnect,
    this.onToggleBroadcast,
    this.onToggleSolo,
    this.onSplit,
  });

  final String? sessionId;
  final Terminal terminal;
  final TerminalController controller;
  final FocusNode focusNode;
  final session_models.ConnectionStatus status;
  final domain.SshProfile? profile;
  final bool broadcastTyping;
  final bool solo;
  final bool active;
  final VoidCallback? onTap;
  final VoidCallback? onReconnect;
  final VoidCallback? onToggleBroadcast;
  final VoidCallback? onToggleSolo;
  final void Function(String draggedSessionId, SplitDirection direction)?
  onSplit;

  @override
  Widget build(BuildContext context) {
    final connected = status == session_models.ConnectionStatus.connected;
    final connecting = status == session_models.ConnectionStatus.connecting;
    final draggable = sessionId != null && onSplit != null;
    final pane = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: active
                ? connected
                      ? AppColors.green
                      : AppColors.amber
                : AppColors.border,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            TerminalView(
              terminal,
              controller: controller,
              focusNode: focusNode,
              autofocus: active,
              padding: EdgeInsets.fromLTRB(16, draggable ? 34 : 16, 16, 16),
              textStyle: const TerminalStyle(
                fontSize: 13,
                height: 1.28,
                fontFamily: 'monospace',
              ),
              theme: portixTerminalTheme,
              cursorType: TerminalCursorType.block,
              alwaysShowCursor: active && connected,
            ),
            if (!connected)
              Positioned.fill(
                child: TerminalConnectionOverlay(
                  profile: profile,
                  connecting: connecting,
                  onReconnect: connecting ? null : onReconnect,
                ),
              ),
            if (onSplit != null) ...[
              PaneDropZone(direction: SplitDirection.left, onAccept: onSplit!),
              PaneDropZone(direction: SplitDirection.right, onAccept: onSplit!),
              PaneDropZone(direction: SplitDirection.top, onAccept: onSplit!),
              PaneDropZone(
                direction: SplitDirection.bottom,
                onAccept: onSplit!,
              ),
            ],
            if (onToggleBroadcast != null || onToggleSolo != null)
              Positioned(
                right: 6,
                top: 6,
                child: PaneControlStrip(
                  broadcastTyping: broadcastTyping,
                  solo: solo,
                  onToggleBroadcast: onToggleBroadcast,
                  onToggleSolo: onToggleSolo,
                ),
              ),
            if (draggable)
              Positioned(
                left: 8,
                top: 7,
                child: PaneDragHandle(sessionId: sessionId!),
              ),
          ],
        ),
      ),
    );
    return pane;
  }
}

class PaneDragHandle extends StatelessWidget {
  const PaneDragHandle({required this.sessionId});

  final String sessionId;

  @override
  Widget build(BuildContext context) {
    return Draggable<String>(
      data: sessionId,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          width: 220,
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.surfaceCard.withValues(alpha: .94),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.green, width: 1.2),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.drag_indicator_rounded,
                color: AppColors.green,
                size: 18,
              ),
              SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Move terminal session',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.text,
                    fontWeight: FontWeight.w900,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      child: Tooltip(
        message: 'Drag terminal pane',
        child: Container(
          width: 30,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.terminal.withValues(alpha: .72),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: AppColors.border.withValues(alpha: .55)),
          ),
          child: const Icon(
            Icons.drag_indicator_rounded,
            color: AppColors.muted,
            size: 16,
          ),
        ),
      ),
    );
  }
}

class PaneControlStrip extends StatelessWidget {
  const PaneControlStrip({
    required this.broadcastTyping,
    required this.solo,
    required this.onToggleBroadcast,
    required this.onToggleSolo,
  });

  final bool broadcastTyping;
  final bool solo;
  final VoidCallback? onToggleBroadcast;
  final VoidCallback? onToggleSolo;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.terminal.withValues(alpha: .78),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border.withValues(alpha: .65)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onToggleBroadcast != null)
            SizedBox.square(
              dimension: 34,
              child: IconButton(
                tooltip: broadcastTyping
                    ? 'Disable broadcast typing'
                    : 'Enable broadcast typing',
                onPressed: onToggleBroadcast,
                padding: EdgeInsets.zero,
                icon: Icon(
                  broadcastTyping
                      ? Icons.keyboard_alt_rounded
                      : Icons.keyboard_alt_outlined,
                  color: broadcastTyping ? AppColors.green : AppColors.muted,
                  size: 18,
                ),
              ),
            ),
          if (onToggleSolo != null)
            SizedBox.square(
              dimension: 34,
              child: IconButton(
                tooltip: solo ? 'Exit solo screen' : 'Solo screen',
                onPressed: onToggleSolo,
                padding: EdgeInsets.zero,
                icon: Icon(
                  solo
                      ? Icons.fullscreen_exit_rounded
                      : Icons.fullscreen_rounded,
                  color: AppColors.muted,
                  size: 18,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class PaneDropZone extends StatelessWidget {
  const PaneDropZone({required this.direction, required this.onAccept});

  final SplitDirection direction;
  final void Function(String draggedSessionId, SplitDirection direction)
  onAccept;

  @override
  Widget build(BuildContext context) {
    final alignment = switch (direction) {
      SplitDirection.left => Alignment.centerLeft,
      SplitDirection.right => Alignment.centerRight,
      SplitDirection.top => Alignment.topCenter,
      SplitDirection.bottom => Alignment.bottomCenter,
    };
    final margin = switch (direction) {
      SplitDirection.left => const EdgeInsets.only(right: 56),
      SplitDirection.right => const EdgeInsets.only(left: 56),
      SplitDirection.top => const EdgeInsets.only(bottom: 56),
      SplitDirection.bottom => const EdgeInsets.only(top: 56),
    };
    final width = switch (direction) {
      SplitDirection.left || SplitDirection.right => 56.0,
      SplitDirection.top || SplitDirection.bottom => null,
    };
    final height = switch (direction) {
      SplitDirection.left || SplitDirection.right => null,
      SplitDirection.top || SplitDirection.bottom => 56.0,
    };

    return Positioned.fill(
      child: IgnorePointer(
        ignoring: false,
        child: Align(
          alignment: alignment,
          child: Padding(
            padding: margin,
            child: DragTarget<String>(
              onAcceptWithDetails: (details) =>
                  onAccept(details.data, direction),
              builder: (context, candidates, rejected) {
                final hovered = candidates.isNotEmpty;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: width,
                  height: height,
                  decoration: BoxDecoration(
                    color: hovered
                        ? AppColors.green.withValues(alpha: .28)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: hovered
                        ? Border.all(color: AppColors.green, width: 1.2)
                        : null,
                  ),
                  child: hovered
                      ? Center(
                          child: Icon(
                            switch (direction) {
                              SplitDirection.left =>
                                Icons.keyboard_arrow_left_rounded,
                              SplitDirection.right =>
                                Icons.keyboard_arrow_right_rounded,
                              SplitDirection.top =>
                                Icons.keyboard_arrow_up_rounded,
                              SplitDirection.bottom =>
                                Icons.keyboard_arrow_down_rounded,
                            },
                            color: AppColors.green,
                            size: 22,
                          ),
                        )
                      : null,
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
