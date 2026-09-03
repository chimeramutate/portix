import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:xterm/src/core/mouse/button.dart';
import 'package:xterm/src/core/mouse/button_state.dart';
import 'package:xterm/src/terminal_view.dart';
import 'package:xterm/src/ui/controller.dart';
import 'package:xterm/src/ui/gesture/gesture_detector.dart';
import 'package:xterm/src/ui/pointer_input.dart';
import 'package:xterm/src/ui/render.dart';

class TerminalGestureHandler extends StatefulWidget {
  const TerminalGestureHandler({
    super.key,
    required this.terminalView,
    required this.terminalController,
    this.child,
    this.onTapUp,
    this.onSingleTapUp,
    this.onTapDown,
    this.onSecondaryTapDown,
    this.onSecondaryTapUp,
    this.onTertiaryTapDown,
    this.onTertiaryTapUp,
    this.readOnly = false,
  });

  final TerminalViewState terminalView;

  final TerminalController terminalController;

  final Widget? child;

  final GestureTapUpCallback? onTapUp;

  final GestureTapUpCallback? onSingleTapUp;

  final GestureTapDownCallback? onTapDown;

  final GestureTapDownCallback? onSecondaryTapDown;

  final GestureTapUpCallback? onSecondaryTapUp;

  final GestureTapDownCallback? onTertiaryTapDown;

  final GestureTapUpCallback? onTertiaryTapUp;

  final bool readOnly;

  @override
  State<TerminalGestureHandler> createState() => _TerminalGestureHandlerState();
}

const _terminalDebugEnabled = bool.fromEnvironment('PORTIX_TERMINAL_DEBUG');

void _terminalDebugLog(String message) {
  if (_terminalDebugEnabled) {
    dev.log(message, name: 'portix.terminal.gesture');
  }
}

class _TerminalGestureHandlerState extends State<TerminalGestureHandler> {
  TerminalViewState get terminalView => widget.terminalView;

  RenderTerminal get renderTerminal => terminalView.renderTerminal;

  DragStartDetails? _lastDragStartDetails;

  LongPressStartDetails? _lastLongPressStartDetails;

  bool _dragSelectionActive = false;

  /// Tracks a periodic timer that auto-scrolls the viewport while a selection
  /// is being dragged past the top/bottom edge of the visible area, so block
  /// selections can extend past what currently fits on screen.
  Timer? _selectionAutoScrollTimer;

  /// The last pointer position reported during a selection drag.  Kept so the
  /// auto-scroll timer can keep extending the selection while the pointer sits
  /// stationary against an edge.
  Offset? _lastPointerLocal;

  @override
  Widget build(BuildContext context) {
    return TerminalGestureDetector(
      child: widget.child,
      onTapUp: widget.onTapUp,
      onSingleTapUp: onSingleTapUp,
      onTapDown: onTapDown,
      onSecondaryTapDown: onSecondaryTapDown,
      onSecondaryTapUp: onSecondaryTapUp,
      onTertiaryTapDown: onSecondaryTapDown,
      onTertiaryTapUp: onSecondaryTapUp,
      onLongPressStart: onLongPressStart,
      onLongPressMoveUpdate: onLongPressMoveUpdate,
      // onLongPressUp: onLongPressUp,
      onDragStart: onDragStart,
      onDragUpdate: onDragUpdate,
      onDragEnd: onDragEnd,
      onDragCancel: onDragCancel,
      onDoubleTapDown: onDoubleTapDown,
    );
  }

  bool get _shouldSendTapEvent =>
      !widget.readOnly &&
      widget.terminalController.shouldSendPointerInput(PointerInput.tap);

  void _tapDown(
    GestureTapDownCallback? callback,
    TapDownDetails details,
    TerminalMouseButton button, {
    bool forceCallback = false,
  }) {
    // Check if the terminal should and can handle the tap down event.
    var handled = false;
    if (_shouldSendTapEvent) {
      handled = renderTerminal.mouseEvent(
        button,
        TerminalMouseButtonState.down,
        details.localPosition,
      );
    }
    // If the event was not handled by the terminal, use the supplied callback.
    if (!handled || forceCallback) {
      callback?.call(details);
    }
  }

  void _tapUp(
    GestureTapUpCallback? callback,
    TapUpDetails details,
    TerminalMouseButton button, {
    bool forceCallback = false,
  }) {
    // Check if the terminal should and can handle the tap up event.
    var handled = false;
    if (_shouldSendTapEvent) {
      handled = renderTerminal.mouseEvent(
        button,
        TerminalMouseButtonState.up,
        details.localPosition,
      );
    }
    // If the event was not handled by the terminal, use the supplied callback.
    if (!handled || forceCallback) {
      callback?.call(details);
    }
  }

  void onTapDown(TapDownDetails details) {
    // onTapDown is special, as it will always call the supplied callback.
    // The TerminalView depends on it to bring the terminal into focus.
    _tapDown(
      widget.onTapDown,
      details,
      TerminalMouseButton.left,
      forceCallback: true,
    );
  }

  void onSingleTapUp(TapUpDetails details) {
    _tapUp(widget.onSingleTapUp, details, TerminalMouseButton.left);
  }

  void onSecondaryTapDown(TapDownDetails details) {
    _tapDown(widget.onSecondaryTapDown, details, TerminalMouseButton.right);
  }

  void onSecondaryTapUp(TapUpDetails details) {
    _tapUp(widget.onSecondaryTapUp, details, TerminalMouseButton.right);
  }

  void onTertiaryTapDown(TapDownDetails details) {
    _tapDown(widget.onTertiaryTapDown, details, TerminalMouseButton.middle);
  }

  void onTertiaryTapUp(TapUpDetails details) {
    _tapUp(widget.onTertiaryTapUp, details, TerminalMouseButton.right);
  }

  void onDoubleTapDown(TapDownDetails details) {
    renderTerminal.selectWord(details.localPosition);
  }

  void onLongPressStart(LongPressStartDetails details) {
    _lastLongPressStartDetails = details;
    renderTerminal.selectWord(details.localPosition);
  }

  void onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    renderTerminal.selectWord(
      _lastLongPressStartDetails!.localPosition,
      details.localPosition,
    );
  }

  // void onLongPressUp() {}

  void onDragStart(DragStartDetails details) {
    _lastDragStartDetails = details;
    _terminalDebugLog(
      'dragStart kind=${details.kind} pos=${details.localPosition} '
      'mouseMode=${terminalView.widget.terminal.mouseMode} '
      'altBuffer=${terminalView.widget.terminal.isUsingAltBuffer} '
      'selection=${widget.terminalController.selection}',
    );

    if (details.kind == PointerDeviceKind.mouse) {
      _dragSelectionActive = true;
      widget.terminalController.setSuspendPointerInput(true);
      renderTerminal.selectCharacters(details.localPosition);
      _lastPointerLocal = details.localPosition;
      _startSelectionAutoScroll();
      _terminalDebugLog(
        'dragStart mouse selection=${widget.terminalController.selection} '
        'suspended=${widget.terminalController.suspendedPointerInputs}',
      );
      return;
    }

    renderTerminal.selectWord(details.localPosition);
    _terminalDebugLog(
      'dragStart touch/other selection=${widget.terminalController.selection}',
    );
  }

  void onDragUpdate(DragUpdateDetails details) {
    _lastPointerLocal = details.localPosition;
    renderTerminal.selectCharacters(
      _lastDragStartDetails!.localPosition,
      details.localPosition,
    );
    _terminalDebugLog(
      'dragUpdate from=${_lastDragStartDetails!.localPosition} '
      'to=${details.localPosition} '
      'selection=${widget.terminalController.selection}',
    );
  }

  void onDragEnd(DragEndDetails details) {
    _terminalDebugLog(
      'dragEnd velocity=${details.velocity.pixelsPerSecond} '
      'selection=${widget.terminalController.selection}',
    );
    if (_dragSelectionActive) {
      _dragSelectionActive = false;
      widget.terminalController.setSuspendPointerInput(false);
    }
    _stopSelectionAutoScroll();
    _terminalDebugLog(
      'dragEnd suspended=${widget.terminalController.suspendedPointerInputs}',
    );
    _lastDragStartDetails = null;
  }

  void onDragCancel() {
    _terminalDebugLog(
        'dragCancel selection=${widget.terminalController.selection}');
    if (_dragSelectionActive) {
      _dragSelectionActive = false;
      widget.terminalController.setSuspendPointerInput(false);
    }
    _stopSelectionAutoScroll();
    _terminalDebugLog(
      'dragCancel suspended=${widget.terminalController.suspendedPointerInputs}',
    );
    _lastDragStartDetails = null;
  }

  void _startSelectionAutoScroll() {
    if (_selectionAutoScrollTimer?.isActive == true) return;
    _selectionAutoScrollTimer = Timer.periodic(
      const Duration(milliseconds: 16),
      _onSelectionAutoScrollTick,
    );
  }

  void _stopSelectionAutoScroll() {
    _selectionAutoScrollTimer?.cancel();
    _selectionAutoScrollTimer = null;
    _lastPointerLocal = null;
  }

  void _onSelectionAutoScrollTick(Timer timer) {
    if (!_dragSelectionActive || _lastPointerLocal == null) return;
    if (!terminalView.mounted) {
      _stopSelectionAutoScroll();
      return;
    }
    // In the alt buffer there is no scrollback, so there is nothing to scroll
    // into view; auto-scroll only applies to selections in the main buffer.
    if (terminalView.widget.terminal.isUsingAltBuffer) return;

    final delta = renderTerminal.getSelectionDragScrollDelta(_lastPointerLocal!);
    if (delta == 0.0) return;

    // Move the viewport, then re-extend the selection.  Because the viewport
    // moved, the same pointer position now maps to further buffer content, so
    // selectCharacters picks up the newly revealed lines automatically.
    terminalView.scrollBy(delta);
    renderTerminal.selectCharacters(
      _lastDragStartDetails!.localPosition,
      _lastPointerLocal!,
    );
  }
}
