import 'dart:developer' as dev;
import 'dart:math' show max;
import 'dart:ui';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:xterm/src/core/buffer/cell_offset.dart';
import 'package:xterm/src/core/buffer/range.dart';
import 'package:xterm/src/core/buffer/segment.dart';
import 'package:xterm/src/core/mouse/button.dart';
import 'package:xterm/src/core/mouse/button_state.dart';
import 'package:xterm/src/terminal.dart';
import 'package:xterm/src/ui/controller.dart';
import 'package:xterm/src/ui/cursor_type.dart';
import 'package:xterm/src/ui/painter.dart';
import 'package:xterm/src/ui/selection_mode.dart';
import 'package:xterm/src/ui/terminal_size.dart';
import 'package:xterm/src/ui/terminal_text_style.dart';
import 'package:xterm/src/ui/terminal_theme.dart';

typedef EditableRectCallback = void Function(Rect rect, Rect caretRect);

const _terminalRenderDebugEnabled = bool.fromEnvironment('PORTIX_TERMINAL_DEBUG');

void _terminalRenderDebugLog(String message) {
  if (_terminalRenderDebugEnabled) {
    dev.log(message, name: 'portix.terminal.render');
  }
}

class RenderTerminal extends RenderBox with RelayoutWhenSystemFontsChangeMixin {
  RenderTerminal({
    required Terminal terminal,
    required TerminalController controller,
    required ViewportOffset offset,
    required EdgeInsets padding,
    required bool autoResize,
    required TerminalStyle textStyle,
    required TextScaler textScaler,
    required TerminalTheme theme,
    required FocusNode focusNode,
    required TerminalCursorType cursorType,
    required bool alwaysShowCursor,
    EditableRectCallback? onEditableRect,
    String? composingText,
  })  : _terminal = terminal,
        _controller = controller,
        _offset = offset,
        _padding = padding,
        _autoResize = autoResize,
        _focusNode = focusNode,
        _cursorType = cursorType,
        _alwaysShowCursor = alwaysShowCursor,
        _onEditableRect = onEditableRect,
        _composingText = composingText,
        _painter = TerminalPainter(
          theme: theme,
          textStyle: textStyle,
          textScaler: textScaler,
        );

  Terminal _terminal;
  set terminal(Terminal terminal) {
    if (_terminal == terminal) return;
    if (attached) _terminal.removeListener(_onTerminalChange);
    _terminal = terminal;
    if (attached) _terminal.addListener(_onTerminalChange);
    _resizeTerminalIfNeeded();
    markNeedsLayout();
  }

  TerminalController _controller;
  set controller(TerminalController controller) {
    if (_controller == controller) return;
    if (attached) _controller.removeListener(_onControllerUpdate);
    _controller = controller;
    if (attached) _controller.addListener(_onControllerUpdate);
    markNeedsLayout();
  }

  ViewportOffset _offset;
  set offset(ViewportOffset value) {
    if (value == _offset) return;
    if (attached) _offset.removeListener(_onScroll);
    _offset = value;
    if (attached) _offset.addListener(_onScroll);
    markNeedsLayout();
  }

  EdgeInsets _padding;
  set padding(EdgeInsets value) {
    if (value == _padding) return;
    _padding = value;
    markNeedsLayout();
  }

  bool _autoResize;
  set autoResize(bool value) {
    if (value == _autoResize) return;
    _autoResize = value;
    markNeedsLayout();
  }

  set textStyle(TerminalStyle value) {
    if (value == _painter.textStyle) return;
    _painter.textStyle = value;
    markNeedsLayout();
  }

  set textScaler(TextScaler value) {
    if (value == _painter.textScaler) return;
    _painter.textScaler = value;
    markNeedsLayout();
  }

  set theme(TerminalTheme value) {
    if (value == _painter.theme) return;
    _painter.theme = value;
    markNeedsPaint();
  }

  FocusNode _focusNode;
  set focusNode(FocusNode value) {
    if (value == _focusNode) return;
    if (attached) _focusNode.removeListener(_onFocusChange);
    _focusNode = value;
    if (attached) _focusNode.addListener(_onFocusChange);
    markNeedsPaint();
  }

  TerminalCursorType _cursorType;
  set cursorType(TerminalCursorType value) {
    if (value == _cursorType) return;
    _cursorType = value;
    markNeedsPaint();
  }

  bool _alwaysShowCursor;
  set alwaysShowCursor(bool value) {
    if (value == _alwaysShowCursor) return;
    _alwaysShowCursor = value;
    markNeedsPaint();
  }

  EditableRectCallback? _onEditableRect;
  set onEditableRect(EditableRectCallback? value) {
    if (value == _onEditableRect) return;
    _onEditableRect = value;
    markNeedsLayout();
  }

  String? _composingText;
  set composingText(String? value) {
    if (value == _composingText) return;
    _composingText = value;
    markNeedsPaint();
  }

  TerminalSize? _viewportSize;

  final TerminalPainter _painter;

  var _stickToBottom = true;

  void _onScroll() {
    _stickToBottom = _scrollOffset >= _maxScrollExtent;
    markNeedsLayout();
    _notifyEditableRect();
  }

  void _onFocusChange() {
    markNeedsPaint();
  }

  void _onTerminalChange() {
    markNeedsLayout();
    _notifyEditableRect();
  }

  void _onControllerUpdate() {
    markNeedsLayout();
  }

  @override
  final isRepaintBoundary = true;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _offset.addListener(_onScroll);
    _terminal.addListener(_onTerminalChange);
    _controller.addListener(_onControllerUpdate);
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void detach() {
    super.detach();
    _offset.removeListener(_onScroll);
    _terminal.removeListener(_onTerminalChange);
    _controller.removeListener(_onControllerUpdate);
    _focusNode.removeListener(_onFocusChange);
  }

  @override
  bool hitTestSelf(Offset position) {
    return true;
  }

  @override
  void systemFontsDidChange() {
    _painter.clearFontCache();
    super.systemFontsDidChange();
  }

  @override
  void performLayout() {
    size = constraints.biggest;

    _updateViewportSize();

    _updateScrollOffset();

    if (_stickToBottom) {
      _offset.correctBy(_maxScrollExtent - _scrollOffset);
    }
  }

  /// Total height of the terminal in pixels. Includes scrollback buffer.
  double get _terminalHeight =>
      _terminal.buffer.lines.length * _painter.cellSize.height;

  /// The distance from the top of the terminal to the top of the viewport.
  // double get _scrollOffset => _offset.pixels;
  double get _scrollOffset {
    // return _offset.pixels ~/ _painter.cellSize.height * _painter.cellSize.height;
    return _offset.pixels;
  }

  /// The height of a terminal line in pixels. This includes the line spacing.
  /// Height of the entire terminal is expected to be a multiple of this value.
  double get lineHeight => _painter.cellSize.height;

  /// Get the top-left corner of the cell at [cellOffset] in pixels.
  Offset getOffset(CellOffset cellOffset) {
    final row = cellOffset.y;
    final col = cellOffset.x;
    final x = col * _painter.cellSize.width;
    final y = row * _painter.cellSize.height;
    return Offset(x + _padding.left, y + _padding.top - _scrollOffset);
  }

  /// Get the [CellOffset] of the cell that [offset] is in.
  ///
  /// In alternate buffer (`less`, `vim`, `man`, etc), the visible viewport is
  /// already painted relative to the currently visible rows, so hit-testing must
  /// stay in viewport coordinates instead of adding scrollback again.
  CellOffset getCellOffset(Offset offset) {
    final x = offset.dx - _padding.left;
    final y = offset.dy - _padding.top;
    final col = x ~/ _painter.cellSize.width;

    int row;
    if (_terminal.isUsingAltBuffer) {
      final viewportRow = y ~/ _painter.cellSize.height;
      row = _terminal.buffer.scrollBack + viewportRow;
    } else {
      final yWithScroll = y + _scrollOffset;
      row = yWithScroll ~/ _painter.cellSize.height;
    }

    final bufferLineCount = _terminal.buffer.lines.length;
    final result = CellOffset(
      col.clamp(0, _terminal.viewWidth - 1),
      row.clamp(0, max(0, bufferLineCount - 1)),
    );
    _terminalRenderDebugLog(
      'getCellOffset offset=$offset col=$col row=$row result=$result '
      'altBuffer=${_terminal.isUsingAltBuffer} scrollOffset=$_scrollOffset '
      'bufferLineCount=$bufferLineCount view=${_terminal.viewWidth}x${_terminal.viewHeight}',
    );
    return result;
  }

  /// Selects entire words in the terminal that contains [from] and [to].
  void selectWord(Offset from, [Offset? to]) {
    final fromOffset = getCellOffset(from);
    final fromBoundary = _terminal.buffer.getWordBoundary(fromOffset);
    if (fromBoundary == null) return;
    if (to == null) {
      _controller.setSelection(
        _terminal.buffer.createAnchorFromOffset(fromBoundary.begin),
        _terminal.buffer.createAnchorFromOffset(fromBoundary.end),
        mode: SelectionMode.line,
      );
    } else {
      final toOffset = getCellOffset(to);
      final toBoundary = _terminal.buffer.getWordBoundary(toOffset);
      if (toBoundary == null) return;
      final range = fromBoundary.merge(toBoundary);
      _controller.setSelection(
        _terminal.buffer.createAnchorFromOffset(range.begin),
        _terminal.buffer.createAnchorFromOffset(range.end),
        mode: SelectionMode.line,
      );
    }
  }

  /// Selects characters in the terminal that starts from [from] to [to]. At
  /// least one cell is selected even if [from] and [to] are same.
  void selectCharacters(Offset from, [Offset? to]) {
    final fromPosition = getCellOffset(from);
    if (to == null) {
      final base = CellOffset(
        fromPosition.x.clamp(0, _terminal.viewWidth - 1),
        fromPosition.y.clamp(0, max(0, _terminal.buffer.lines.length - 1)),
      );
      _controller.setSelection(
        _terminal.buffer.createAnchorFromOffset(base),
        _terminal.buffer.createAnchorFromOffset(base),
        mode: _controller.selectionMode,
      );
      return;
    }

    var toPosition = getCellOffset(to);
    if (toPosition.x >= fromPosition.x) {
      toPosition = CellOffset(toPosition.x + 1, toPosition.y);
    }

    final base = CellOffset(
      fromPosition.x.clamp(0, _terminal.viewWidth - 1),
      fromPosition.y.clamp(0, max(0, _terminal.buffer.lines.length - 1)),
    );
    final extent = CellOffset(
      toPosition.x.clamp(0, _terminal.viewWidth - 1),
      toPosition.y.clamp(0, max(0, _terminal.buffer.lines.length - 1)),
    );

    _controller.setSelection(
      _terminal.buffer.createAnchorFromOffset(base),
      _terminal.buffer.createAnchorFromOffset(extent),
      mode: _controller.selectionMode,
    );
  }

  /// Send a mouse event at [offset] with [button] being currently in [buttonState].
  bool mouseEvent(
    TerminalMouseButton button,
    TerminalMouseButtonState buttonState,
    Offset offset,
  ) {
    final position = getCellOffset(offset);
    return _terminal.mouseInput(button, buttonState, position);
  }

  void _notifyEditableRect() {
    final cursor = localToGlobal(cursorOffset);

    final rect = Rect.fromLTRB(
      cursor.dx,
      cursor.dy,
      size.width,
      cursor.dy + _painter.cellSize.height,
    );

    final caretRect = cursor & _painter.cellSize;

    _onEditableRect?.call(rect, caretRect);
  }

  /// Update the viewport size in cells based on the current widget size in
  /// pixels.
  void _updateViewportSize() {
    if (size <= _painter.cellSize) {
      return;
    }

    final viewportSize = TerminalSize(
      size.width ~/ _painter.cellSize.width,
      _viewportHeight ~/ _painter.cellSize.height,
    );

    if (_viewportSize != viewportSize) {
      _viewportSize = viewportSize;
      _resizeTerminalIfNeeded();
    }
  }

  /// Notify the underlying terminal that the viewport size has changed.
  void _resizeTerminalIfNeeded() {
    if (_autoResize && _viewportSize != null) {
      _terminal.resize(
        _viewportSize!.width,
        _viewportSize!.height,
        _painter.cellSize.width.round(),
        _painter.cellSize.height.round(),
      );
    }
  }

  /// Update the scroll offset based on the current terminal state. This should
  /// be called in [performLayout] after the viewport size has been updated.
  void _updateScrollOffset() {
    _offset.applyViewportDimension(_viewportHeight);
    _offset.applyContentDimensions(0, _maxScrollExtent);
  }

  bool get _isComposingText {
    return _composingText != null && _composingText!.isNotEmpty;
  }

  bool get _shouldShowCursor {
    return _terminal.cursorVisibleMode || _alwaysShowCursor || _isComposingText;
  }

  double get _viewportHeight {
    return size.height - _padding.vertical;
  }

  double get _maxScrollExtent {
    return max(_terminalHeight - _viewportHeight, 0.0);
  }

  double get _lineOffset {
    return -_scrollOffset + _padding.top;
  }

  /// The offset of the cursor from the top left corner of this render object.
  Offset get cursorOffset {
    double yOffset;

    if (_terminal.isUsingAltBuffer) {
      // In alt buffer, cursor position is relative to visible viewport
      final cursorLine = _terminal.buffer.absoluteCursorY - _terminal.buffer.scrollBack;
      yOffset = cursorLine * _painter.cellSize.height + _padding.top;
    } else {
      yOffset = _terminal.buffer.absoluteCursorY * _painter.cellSize.height + _lineOffset;
    }

    return Offset(
      _terminal.buffer.cursorX * _painter.cellSize.width,
      yOffset,
    );
  }

  Size get cellSize {
    return _painter.cellSize;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    _paint(context, offset);
    context.setWillChangeHint();
  }

  void _paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;

    final lines = _terminal.buffer.lines;
    if (lines.length == 0) {
      return;
    }

    final charHeight = _painter.cellSize.height;
    final maxLineIndex = lines.length - 1;

    // In alternate buffer, the application controls scroll internally.
    // We need to account for this by using the buffer's scroll position.
    int firstLine;
    int lastLine;

    if (_terminal.isUsingAltBuffer) {
      // Use viewport height inside terminal padding and derive the number of
      // visible rows defensively to avoid requesting one line past the buffer.
      final bufferScrollOffset = _terminal.buffer.scrollBack;
      final visibleRows = max(1, (_viewportHeight / charHeight).ceil());
      firstLine = bufferScrollOffset.clamp(0, maxLineIndex);
      lastLine = (firstLine + visibleRows - 1).clamp(firstLine, maxLineIndex);
    } else {
      // Normal scrollback buffer behavior.
      final firstLineOffset = (_scrollOffset - _padding.top).clamp(
        0.0,
        _maxScrollExtent,
      );
      final lastLineOffset = (_scrollOffset + _viewportHeight).clamp(
        0.0,
        _maxScrollExtent + _viewportHeight,
      );

      firstLine = (firstLineOffset ~/ charHeight).clamp(0, maxLineIndex);
      lastLine = (lastLineOffset / charHeight).ceil().clamp(firstLine, maxLineIndex);
    }

    for (var i = firstLine; i <= lastLine; i++) {
      // Calculate the Y offset based on whether we're in alt buffer or not
      double yOffset;
      if (_terminal.isUsingAltBuffer) {
        // In alt buffer, the line position is relative to the first visible line
        yOffset = (i - firstLine) * charHeight + _padding.top;
      } else {
        yOffset = i * charHeight + _lineOffset;
      }

      _painter.paintLine(
        canvas,
        offset.translate(0, yOffset.truncateToDouble()),
        lines[i],
      );
    }

    if (_terminal.buffer.absoluteCursorY >= firstLine &&
        _terminal.buffer.absoluteCursorY <= lastLine) {
      if (_isComposingText) {
        _paintComposingText(canvas, offset + cursorOffset);
      }

      if (_shouldShowCursor) {
        _painter.paintCursor(
          canvas,
          offset + cursorOffset,
          cursorType: _cursorType,
          hasFocus: _focusNode.hasFocus,
        );
      }
    }

    _paintHighlights(
      canvas,
      _controller.highlights,
      firstLine,
      lastLine,
    );

    if (_controller.selection != null) {
      _paintSelection(
        canvas,
        _controller.selection!,
        firstLine,
        lastLine,
      );
    }
  }

  /// Paints the text that is currently being composed in IME to [canvas] at
  /// [offset]. [offset] is usually the cursor position.
  void _paintComposingText(Canvas canvas, Offset offset) {
    final composingText = _composingText;
    if (composingText == null) {
      return;
    }

    final style = _painter.textStyle.toTextStyle(
      color: _painter.resolveForegroundColor(_terminal.cursor.foreground),
      backgroundColor: _painter.theme.background,
      underline: true,
    );

    final builder = ParagraphBuilder(style.getParagraphStyle());
    builder.addPlaceholder(
      offset.dx,
      _painter.cellSize.height,
      PlaceholderAlignment.middle,
    );
    builder.pushStyle(
      style.getTextStyle(textScaler: _painter.textScaler),
    );
    builder.addText(composingText);

    final paragraph = builder.build();
    paragraph.layout(ParagraphConstraints(width: size.width));

    canvas.drawParagraph(paragraph, Offset(0, offset.dy));
  }

  void _paintSelection(
    Canvas canvas,
    BufferRange selection,
    int firstLine,
    int lastLine,
  ) {
    for (final segment in selection.toSegments()) {
      if (segment.line >= _terminal.buffer.lines.length) {
        break;
      }

      if (segment.line < firstLine) {
        continue;
      }

      if (segment.line > lastLine) {
        break;
      }

      _paintSegment(canvas, segment, _painter.theme.selection, firstLine);
    }
  }

  void _paintHighlights(
    Canvas canvas,
    List<TerminalHighlight> highlights,
    int firstLine,
    int lastLine,
  ) {
    for (var highlight in _controller.highlights) {
      final range = highlight.range?.normalized;

      if (range == null ||
          range.begin.y > lastLine ||
          range.end.y < firstLine) {
        continue;
      }

      for (var segment in range.toSegments()) {
        if (segment.line < firstLine) {
          continue;
        }

        if (segment.line > lastLine) {
          break;
        }

        _paintSegment(canvas, segment, highlight.color, firstLine);
      }
    }
  }

  @pragma('vm:prefer-inline')
  void _paintSegment(Canvas canvas, BufferSegment segment, Color color, [int? firstLineOverride]) {
    final start = segment.start ?? 0;
    final end = segment.end ?? _terminal.viewWidth;

    // Calculate the Y offset based on whether we're in alt buffer or not
    double yOffset;
    final firstLine = firstLineOverride ?? 0;
    if (_terminal.isUsingAltBuffer) {
      // In alt buffer, segment.line is absolute and we need to adjust relative to firstLine
      yOffset = (segment.line - firstLine) * _painter.cellSize.height + _padding.top;
    } else {
      yOffset = segment.line * _painter.cellSize.height + _lineOffset;
    }

    final startOffset = Offset(
      start * _painter.cellSize.width,
      yOffset,
    );

    _painter.paintHighlight(canvas, startOffset, end - start, color);
  }
}
