part of '../terminal_workspace_view.dart';

class TerminalPane extends StatelessWidget {
  const TerminalPane({
    required this.terminal,
    required this.controller,
    required this.scrollController,
    required this.focusNode,
    required this.terminalViewKey,
    this.sessionId,
    this.status = session_models.ConnectionStatus.connected,
    this.profile,
    this.suggestion,
    this.suggestionCandidates = const [],
    this.suggestionSuffix,
    this.broadcastTyping = false,
    this.solo = false,
    this.active = false,
    this.keyboardEnabled = true,
    this.allowPaneDrag = false,
    this.onTap,
    this.onReconnect,
    this.onToggleBroadcast,
    this.onToggleSolo,
    this.onSplit,
  });

  final String? sessionId;
  final Terminal terminal;
  final TerminalController controller;
  final ScrollController scrollController;
  final FocusNode focusNode;
  final GlobalKey<TerminalViewState> terminalViewKey;
  final session_models.ConnectionStatus status;
  final domain.SshProfile? profile;
  final TerminalSuggestion? suggestion;
  final List<TerminalSuggestion> suggestionCandidates;
  final String? suggestionSuffix;
  final bool broadcastTyping;
  final bool solo;
  final bool active;
  final bool keyboardEnabled;
  final bool allowPaneDrag;
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
    final draggable = allowPaneDrag && sessionId != null && onSplit != null;
    final pane = GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        focusNode.requestFocus();
        onTap?.call();
      },
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
            ScrollConfiguration(
              behavior: ScrollConfiguration.of(
                context,
              ).copyWith(scrollbars: false),
              child: TerminalView(
                terminal,
                key: terminalViewKey,
                controller: controller,
                scrollController: scrollController,
                focusNode: focusNode,
                autofocus: keyboardEnabled && active,
                readOnly: !keyboardEnabled,
                mouseCursor: SystemMouseCursors.text,
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
            ),
            if (!connected)
              Positioned.fill(
                child: TerminalConnectionOverlay(
                  profile: profile,
                  connecting: connecting,
                  onReconnect: connecting ? null : onReconnect,
                ),
              ),
            if (connected &&
                active &&
                suggestion != null &&
                suggestionSuffix != null)
              TerminalInlineSuggestion(
                terminal: terminal,
                terminalViewKey: terminalViewKey,
                text: suggestionSuffix!,
              ),
            if (connected && active && suggestionCandidates.isNotEmpty)
              TerminalCompletionMenu(
                terminal: terminal,
                terminalViewKey: terminalViewKey,
                suggestions: suggestionCandidates,
                selectedSuggestion: suggestion,
              ),
            if (onSplit != null)
              Positioned.fill(
                child: ValueListenableBuilder<bool>(
                  valueListenable: PaneDragHandle.dragging,
                  builder: (context, dragging, child) {
                    if (!dragging) return const SizedBox.shrink();
                    return Stack(
                      children: [
                        PaneDropZone(
                          direction: SplitDirection.left,
                          onAccept: onSplit!,
                        ),
                        PaneDropZone(
                          direction: SplitDirection.right,
                          onAccept: onSplit!,
                        ),
                        PaneDropZone(
                          direction: SplitDirection.top,
                          onAccept: onSplit!,
                        ),
                        PaneDropZone(
                          direction: SplitDirection.bottom,
                          onAccept: onSplit!,
                        ),
                      ],
                    );
                  },
                ),
              ),
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

class TerminalCompletionMenu extends StatefulWidget {
  const TerminalCompletionMenu({
    required this.terminal,
    required this.terminalViewKey,
    required this.suggestions,
    required this.selectedSuggestion,
  });

  final Terminal terminal;
  final GlobalKey<TerminalViewState> terminalViewKey;
  final List<TerminalSuggestion> suggestions;
  final TerminalSuggestion? selectedSuggestion;

  @override
  State<TerminalCompletionMenu> createState() => _TerminalCompletionMenuState();
}

class _TerminalCompletionMenuState extends State<TerminalCompletionMenu> {
  static const _rowHeight = 22.0;

  @override
  void initState() {
    super.initState();
    widget.terminal.addListener(_handleTerminalChanged);
  }

  @override
  void didUpdateWidget(covariant TerminalCompletionMenu oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.terminal != widget.terminal) {
      oldWidget.terminal.removeListener(_handleTerminalChanged);
      widget.terminal.addListener(_handleTerminalChanged);
    }
  }

  @override
  void dispose() {
    widget.terminal.removeListener(_handleTerminalChanged);
    super.dispose();
  }

  void _handleTerminalChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cursorRect = widget.terminalViewKey.currentState?.cursorRect;
    if (widget.suggestions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: IgnorePointer(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final visibleSuggestions = widget.suggestions.take(6).toList();
            final menuHeight = visibleSuggestions.length * _rowHeight;
            final menuWidth = (constraints.maxWidth - 32)
                .clamp(220.0, 560.0)
                .toDouble();
            final maxLeft = (constraints.maxWidth - menuWidth - 16)
                .clamp(16.0, constraints.maxWidth)
                .toDouble();
            final fallbackTop = (constraints.maxHeight - menuHeight - 52)
                .clamp(12.0, constraints.maxHeight)
                .toDouble();
            final left = (cursorRect?.left ?? 16.0)
                .clamp(16.0, maxLeft)
                .toDouble();
            final topBelow = (cursorRect?.bottom ?? fallbackTop) + 12;
            final topAbove = (cursorRect?.top ?? fallbackTop) - menuHeight - 12;
            final top = topBelow + menuHeight <= constraints.maxHeight - 12
                ? topBelow
                : topAbove.clamp(12.0, constraints.maxHeight).toDouble();

            return Stack(
              children: [
                Positioned(
                  left: left,
                  top: top,
                  width: menuWidth,
                  height: menuHeight,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.terminal.withValues(alpha: .9),
                      border: Border.all(
                        color: AppColors.border.withValues(alpha: .7),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final suggestion in visibleSuggestions)
                          _TerminalCompletionRow(
                            suggestion: suggestion,
                            selected:
                                suggestion.command ==
                                widget.selectedSuggestion?.command,
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TerminalCompletionRow extends StatelessWidget {
  const _TerminalCompletionRow({
    required this.suggestion,
    required this.selected,
  });

  final TerminalSuggestion suggestion;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = switch (suggestion.source) {
      TerminalSuggestionSource.history => AppColors.green,
      TerminalSuggestionSource.remoteHelp => AppColors.cyan,
    };
    final description = suggestion.description.trim();

    return Container(
      height: _TerminalCompletionMenuState._rowHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      color: selected ? AppColors.primaryBlue.withValues(alpha: .28) : null,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: suggestion.display,
                style: TextStyle(
                  color: selected ? AppColors.text : color,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (description.isNotEmpty)
                TextSpan(
                  text: ' -- $description',
                  style: TextStyle(
                    color: selected ? AppColors.text : AppColors.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          overflow: TextOverflow.ellipsis,
          softWrap: false,
          style: const TextStyle(
            fontSize: 12,
            height: 1,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }
}

class TerminalInlineSuggestion extends StatefulWidget {
  const TerminalInlineSuggestion({
    required this.terminal,
    required this.terminalViewKey,
    required this.text,
  });

  final Terminal terminal;
  final GlobalKey<TerminalViewState> terminalViewKey;
  final String text;

  @override
  State<TerminalInlineSuggestion> createState() =>
      _TerminalInlineSuggestionState();
}

class _TerminalInlineSuggestionState extends State<TerminalInlineSuggestion> {
  @override
  void initState() {
    super.initState();
    widget.terminal.addListener(_handleTerminalChanged);
  }

  @override
  void didUpdateWidget(covariant TerminalInlineSuggestion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.terminal != widget.terminal) {
      oldWidget.terminal.removeListener(_handleTerminalChanged);
      widget.terminal.addListener(_handleTerminalChanged);
    }
  }

  @override
  void dispose() {
    widget.terminal.removeListener(_handleTerminalChanged);
    super.dispose();
  }

  void _handleTerminalChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cursorRect = widget.terminalViewKey.currentState?.cursorRect;
    if (cursorRect == null || widget.text.isEmpty) {
      return const SizedBox.shrink();
    }
    return Positioned(
      left: cursorRect.right,
      top: cursorRect.top,
      right: 16,
      height: cursorRect.height,
      child: IgnorePointer(
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            widget.text,
            overflow: TextOverflow.fade,
            softWrap: false,
            style: const TextStyle(
              color: Color(0x668FA6BE),
              fontSize: 13,
              height: 1.28,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class PaneDragHandle extends StatelessWidget {
  const PaneDragHandle({required this.sessionId});

  static final ValueNotifier<bool> dragging = ValueNotifier(false);

  final String sessionId;

  @override
  Widget build(BuildContext context) {
    return Draggable<String>(
      data: sessionId,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      onDragStarted: () => dragging.value = true,
      onDragEnd: (_) => dragging.value = false,
      onDraggableCanceled: (_, _) => dragging.value = false,
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
      SplitDirection.left => const EdgeInsets.only(right: 92),
      SplitDirection.right => const EdgeInsets.only(left: 92),
      SplitDirection.top => const EdgeInsets.only(bottom: 92),
      SplitDirection.bottom => const EdgeInsets.only(top: 92),
    };
    final width = switch (direction) {
      SplitDirection.left || SplitDirection.right => 92.0,
      SplitDirection.top || SplitDirection.bottom => null,
    };
    final height = switch (direction) {
      SplitDirection.left || SplitDirection.right => null,
      SplitDirection.top || SplitDirection.bottom => 92.0,
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
                        ? AppColors.green.withValues(alpha: .34)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: hovered
                        ? Border.all(color: AppColors.green, width: 1.8)
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
                            size: 30,
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
