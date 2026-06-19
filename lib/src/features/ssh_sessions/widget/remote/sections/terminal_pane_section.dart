part of '../terminal_workspace_view.dart';

class TerminalPane extends StatefulWidget {
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
    this.copyShortcut = TerminalClipboardShortcut.shiftCtrl,
    this.pasteShortcut = TerminalClipboardShortcut.ctrl,
    this.textColor = AppColors.text,
    this.backgroundColor = AppColors.terminal,
    this.fontFamily = 'monospace',
    this.fontSize = 13,
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
  final TerminalClipboardShortcut copyShortcut;
  final TerminalClipboardShortcut pasteShortcut;
  final Color textColor;
  final Color backgroundColor;
  final String fontFamily;
  final double fontSize;
  final bool allowPaneDrag;
  final VoidCallback? onTap;
  final VoidCallback? onReconnect;
  final VoidCallback? onToggleBroadcast;
  final VoidCallback? onToggleSolo;
  final void Function(String draggedSessionId, SplitDirection direction)?
  onSplit;

  @override
  State<TerminalPane> createState() => _TerminalPaneState();
}

class _TerminalPaneState extends State<TerminalPane> {
  bool _pointerInputSuspended = false;

  @override
  void initState() {
    super.initState();
    widget.terminal.addListener(_onTerminalChanged);
    // Sync suspension state immediately in case the terminal is already in
    // alt-buffer mode when the widget is first built.
    _syncPointerInputSuspension();
  }

  @override
  void didUpdateWidget(covariant TerminalPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.terminal != widget.terminal) {
      oldWidget.terminal.removeListener(_onTerminalChanged);
      widget.terminal.addListener(_onTerminalChanged);
    }
    if (oldWidget.controller != widget.controller) {
      // Release suspension on the old controller so it isn't stuck.
      if (_pointerInputSuspended) {
        oldWidget.controller.setSuspendPointerInput(false);
        _pointerInputSuspended = false;
      }
    }
    _syncPointerInputSuspension();
  }

  @override
  void dispose() {
    widget.terminal.removeListener(_onTerminalChanged);
    // Always clear suspension when the pane is disposed.
    if (_pointerInputSuspended) {
      widget.controller.setSuspendPointerInput(false);
    }
    super.dispose();
  }

  void _onTerminalChanged() {
    if (!mounted) return;
    // Keep the suspension flag in sync every time the terminal emits output
    // (which is when alt-buffer state can change).
    _syncPointerInputSuspension();
    setState(() {});
  }

  // ── Pointer-input suspension ──────────────────────────────────────────────
  //
  // When a TUI app (less, vim, htop, …) is open it uses the terminal's
  // alternate screen buffer AND enables mouse-reporting mode.  In that mode
  // xterm's TerminalGestureHandler forwards every tap/drag to the running app
  // as an escape sequence, preventing text selection.
  //
  // THE ROOT CAUSE: xterm's TerminalScrollGestureHandler wraps the terminal
  // in a Scrollable (InfiniteScrollView) when isAltBuffer == true.  That
  // Scrollable adds its own PanGestureRecognizer which wins the gesture arena
  // for vertical drags — stealing them from xterm's own PanGestureRecognizer
  // that would otherwise call renderTerminal.selectCharacters().
  // As a result, dragging in less always scrolls (or sends mouse events to the
  // app) instead of selecting text — even after pressing Shift+G or any
  // other less shortcut.
  //
  // THE FIX:
  //  1. Set simulateScroll: false on TerminalView so the Scrollable wrapper is
  //     never inserted, leaving xterm's own PanGestureRecognizer free to handle
  //     all drag events as text selection.
  //  2. Replace the Scrollable-based scroll simulation with a Listener on
  //     onPointerSignal: on mouse-wheel events in alt-buffer mode we manually
  //     send ArrowUp / ArrowDown key inputs to the terminal so less / vim still
  //     scroll correctly with the mouse wheel.
  //  3. Keep setSuspendPointerInput in sync with alt-buffer state so that
  //     tap events (single clicks) are also not forwarded to the app during
  //     text-selection drags.

  bool get _isAltBuffer => widget.terminal.isUsingAltBuffer;

  void _syncPointerInputSuspension() {
    final shouldSuspend = _isAltBuffer;
    if (shouldSuspend == _pointerInputSuspended) return;
    _pointerInputSuspended = shouldSuspend;
    widget.controller.setSuspendPointerInput(shouldSuspend);
  }

  // Handle mouse-wheel scroll in alt-buffer mode.
  // Since simulateScroll: false removes xterm's built-in scroll simulation
  // we replicate the same logic here: send ArrowUp / ArrowDown to the terminal.
  void _onPointerSignal(PointerSignalEvent event) {
    if (!_isAltBuffer) return;
    if (event is! PointerScrollEvent) return;
    final dy = event.scrollDelta.dy;
    if (dy == 0) return;
    final key = dy > 0 ? TerminalKey.arrowDown : TerminalKey.arrowUp;
    // Send one arrow key per ~20 px of scroll delta (same ratio xterm uses).
    final steps = (dy.abs() / 20).ceil().clamp(1, 10);
    for (var i = 0; i < steps; i++) {
      widget.terminal.keyInput(key);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final connected =
        widget.status == session_models.ConnectionStatus.connected;
    final connecting =
        widget.status == session_models.ConnectionStatus.connecting;
    final draggable =
        widget.allowPaneDrag &&
        widget.sessionId != null &&
        widget.onSplit != null;

    final pane = GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        widget.focusNode.requestFocus();
        widget.onTap?.call();
      },
      child: Actions(
        actions: {
          if (defaultTargetPlatform == TargetPlatform.linux &&
              widget.copyShortcut == TerminalClipboardShortcut.shiftCtrl)
            TerminalCtrlCCopyAction: TerminalCtrlCCopyAction(
              controller: widget.controller,
            ),
        },
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: widget.active
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
                // Listener handles mouse-wheel scrolling in alt-buffer mode.
                // TerminalView is built with simulateScroll:false so xterm
                // does NOT add its own Scrollable wrapper (InfiniteScrollView)
                // around the terminal.  Without that wrapper, xterm's own
                // PanGestureRecognizer is free to handle drag events as text
                // selection — which is exactly what we need for less/vim/htop.
                // We replicate the scroll behaviour here via onPointerSignal.
                child: Listener(
                  onPointerSignal: _onPointerSignal,
                  behavior: HitTestBehavior.translucent,
                  child: TerminalView(
                    widget.terminal,
                    key: widget.terminalViewKey,
                    controller: widget.controller,
                    scrollController: widget.scrollController,
                    focusNode: widget.focusNode,
                    autofocus: widget.keyboardEnabled && widget.active,
                    readOnly: !widget.keyboardEnabled,
                    hardwareKeyboardOnly: true,
                    // Disable xterm's built-in InfiniteScrollView wrapper.
                    // Without this, the Scrollable inside it registers its own
                    // PanGestureRecognizer which wins the arena and prevents
                    // drag-to-select from working in alt-buffer mode.
                    simulateScroll: false,
                    mouseCursor: SystemMouseCursors.text,
                    padding: EdgeInsets.fromLTRB(
                      16,
                      draggable ? 34 : 16,
                      16,
                      16,
                    ),
                    shortcuts: defaultTargetPlatform == TargetPlatform.linux
                        ? terminalShortcutsFor(
                            copyShortcut: widget.copyShortcut,
                            pasteShortcut: widget.pasteShortcut,
                          )
                        : null,
                    textStyle: TerminalStyle(
                      fontSize: widget.fontSize,
                      height: 1.28,
                      fontFamily: widget.fontFamily,
                    ),
                    theme: terminalThemeForProfile(
                      widget.profile,
                      foreground: widget.textColor,
                      background: widget.backgroundColor,
                    ),
                    cursorType: TerminalCursorType.block,
                    alwaysShowCursor: widget.active && connected,
                  ),
                ),
              ),
              if (!connected)
                Positioned.fill(
                  child: TerminalConnectionOverlay(
                    profile: widget.profile,
                    connecting: connecting,
                    onReconnect: connecting ? null : widget.onReconnect,
                  ),
                ),
              if (connected &&
                  widget.active &&
                  widget.suggestion != null &&
                  widget.suggestionSuffix != null)
                TerminalInlineSuggestion(
                  terminal: widget.terminal,
                  terminalViewKey: widget.terminalViewKey,
                  text: widget.suggestionSuffix!,
                ),
              if (connected &&
                  widget.active &&
                  widget.suggestionCandidates.isNotEmpty)
                TerminalCompletionMenu(
                  terminal: widget.terminal,
                  terminalViewKey: widget.terminalViewKey,
                  suggestions: widget.suggestionCandidates,
                  selectedSuggestion: widget.suggestion,
                ),
              if (connected)
                TerminalSelectionToolbar(
                  terminal: widget.terminal,
                  controller: widget.controller,
                ),
              if (widget.onSplit != null)
                Positioned.fill(
                  child: ValueListenableBuilder<bool>(
                    valueListenable: PaneDragHandle.dragging,
                    builder: (context, dragging, child) {
                      if (!dragging) return const SizedBox.shrink();
                      return Stack(
                        children: [
                          PaneDropZone(
                            direction: SplitDirection.left,
                            onAccept: widget.onSplit!,
                          ),
                          PaneDropZone(
                            direction: SplitDirection.right,
                            onAccept: widget.onSplit!,
                          ),
                          PaneDropZone(
                            direction: SplitDirection.top,
                            onAccept: widget.onSplit!,
                          ),
                          PaneDropZone(
                            direction: SplitDirection.bottom,
                            onAccept: widget.onSplit!,
                          ),
                        ],
                      );
                    },
                  ),
                ),
              if (widget.onToggleBroadcast != null ||
                  widget.onToggleSolo != null)
                Positioned(
                  right: 6,
                  top: 6,
                  child: PaneControlStrip(
                    profile: widget.profile,
                    broadcastTyping: widget.broadcastTyping,
                    solo: widget.solo,
                    onToggleBroadcast: widget.onToggleBroadcast,
                    onToggleSolo: widget.onToggleSolo,
                  ),
                ),
              if (draggable)
                Positioned(
                  left: 8,
                  top: 7,
                  child: PaneDragHandle(sessionId: widget.sessionId!),
                ),
            ],
          ),
        ),
      ),
    );
    return pane;
  }
}

class TerminalSelectionToolbar extends StatefulWidget {
  const TerminalSelectionToolbar({
    required this.terminal,
    required this.controller,
  });

  final Terminal terminal;
  final TerminalController controller;

  @override
  State<TerminalSelectionToolbar> createState() =>
      _TerminalSelectionToolbarState();
}

class _TerminalSelectionToolbarState extends State<TerminalSelectionToolbar> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleSelectionChanged);
  }

  @override
  void didUpdateWidget(covariant TerminalSelectionToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleSelectionChanged);
      widget.controller.addListener(_handleSelectionChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleSelectionChanged);
    super.dispose();
  }

  void _handleSelectionChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _copySelection() async {
    final selection = widget.controller.selection;
    if (selection == null) return;
    final text = widget.terminal.buffer.getText(selection);
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    widget.controller.clearSelection();
  }

  void _toggleSelectionMode() {
    final nextMode = widget.controller.selectionMode == SelectionMode.block
        ? SelectionMode.line
        : SelectionMode.block;
    widget.controller.setSelectionMode(nextMode);
  }

  @override
  Widget build(BuildContext context) {
    final hasSelection = widget.controller.selection != null;
    final blockMode = widget.controller.selectionMode == SelectionMode.block;

    return Positioned(
      right: 8,
      bottom: 8,
      child: Material(
        color: AppColors.surfaceDark.withValues(alpha: .92),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: AppColors.border.withValues(alpha: .7)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: blockMode ? 'Line text select' : 'Block text select',
              child: InkWell(
                onTap: _toggleSelectionMode,
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 34,
                  height: 30,
                  child: Icon(
                    blockMode
                        ? Icons.view_column_rounded
                        : Icons.format_align_left_rounded,
                    size: 16,
                    color: blockMode ? AppColors.cyan : AppColors.muted,
                  ),
                ),
              ),
            ),
            if (hasSelection)
              Tooltip(
                message: 'Copy selected text',
                child: InkWell(
                  onTap: _copySelection,
                  borderRadius: BorderRadius.circular(6),
                  child: const SizedBox(
                    width: 34,
                    height: 30,
                    child: Icon(Icons.copy_rounded, size: 16),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
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
    this.profile,
  });

  final bool broadcastTyping;
  final bool solo;
  final VoidCallback? onToggleBroadcast;
  final VoidCallback? onToggleSolo;
  final domain.SshProfile? profile;

  @override
  Widget build(BuildContext context) {
    final accentColor = profile == null
        ? AppColors.green
        : switch (profile!.color) {
            domain.ProfileColor.green => AppColors.green,
            domain.ProfileColor.cyan => AppColors.cyan,
            domain.ProfileColor.blue => AppColors.primaryBlue,
            domain.ProfileColor.pink => AppColors.danger,
            domain.ProfileColor.amber => AppColors.amber,
          };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.terminal.withValues(alpha: .78),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border.withValues(alpha: .65)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (profile != null) ...[
            const SizedBox(width: 8),
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: accentColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 5),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 100),
              child: Text(
                profile!.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: accentColor,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'Inter',
                ),
              ),
            ),
            const SizedBox(width: 4),
          ],
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
