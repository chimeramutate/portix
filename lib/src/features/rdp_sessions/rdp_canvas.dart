import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../connection_manager/rdp_backend.dart';
import '../../connection_manager/rdp_session_models.dart';

/// A widget that renders the RDP desktop and handles input events.
class RdpCanvas extends StatefulWidget {
  const RdpCanvas({
    super.key,
    required this.sessionId,
    required this.width,
    required this.height,
    required this.backend,
  });

  final String sessionId;
  final int width;
  final int height;
  final RdpBackend backend;

  @override
  State<RdpCanvas> createState() => _RdpCanvasState();
}

class _RdpCanvasState extends State<RdpCanvas> {
  ui.Image? _currentFrame;
  late final StreamSubscription<RdpFrameEvent> _frameSub;
  late Uint8List _frameBuffer;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _frameBuffer = Uint8List(widget.width * widget.height * 4);

    _frameSub = widget.backend.frameStream
        .where((event) => event.sessionId == widget.sessionId)
        .listen(_onFrameUpdate);
  }

  @override
  void dispose() {
    _frameSub.cancel();
    _currentFrame?.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onFrameUpdate(RdpFrameEvent event) {
    // The Rust side sends full frames, so just replace the buffer
    if (event.data.length == _frameBuffer.length) {
      _frameBuffer = Uint8List.fromList(event.data);
    } else {
      // Partial update - apply region
      final stride = widget.width * 4;
      final updateStride = event.width * 4;

      for (int row = 0; row < event.height; row++) {
        final bufY = event.y + row;
        if (bufY >= widget.height) break;
        final bufOffset = bufY * stride + event.x * 4;
        final srcOffset = row * updateStride;

        if (bufOffset + updateStride <= _frameBuffer.length &&
            srcOffset + updateStride <= event.data.length) {
          _frameBuffer.setRange(
            bufOffset,
            bufOffset + updateStride,
            event.data,
            srcOffset,
          );
        }
      }
    }

    _decodeFrame();
  }

  Future<void> _decodeFrame() async {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      _frameBuffer,
      widget.width,
      widget.height,
      ui.PixelFormat.rgba8888,
      (image) => completer.complete(image),
    );
    final image = await completer.future;

    if (mounted) {
      setState(() {
        _currentFrame?.dispose();
        _currentFrame = image;
      });
    } else {
      image.dispose();
    }
  }

  void _onPointerDown(PointerDownEvent event) {
    _focusNode.requestFocus();
    final pos = _toDesktopCoords(event.localPosition);
    final button = _mapMouseButton(event.buttons);
    widget.backend.sendMouseButton(
      widget.sessionId,
      x: pos.dx.toInt(),
      y: pos.dy.toInt(),
      button: button,
      isPressed: true,
    );
  }

  void _onPointerUp(PointerUpEvent event) {
    final pos = _toDesktopCoords(event.localPosition);
    widget.backend.sendMouseButton(
      widget.sessionId,
      x: pos.dx.toInt(),
      y: pos.dy.toInt(),
      button: RdpMouseButton.left,
      isPressed: false,
    );
  }

  void _onPointerHover(PointerHoverEvent event) {
    final pos = _toDesktopCoords(event.localPosition);
    widget.backend.sendMouseMove(
      widget.sessionId,
      x: pos.dx.toInt(),
      y: pos.dy.toInt(),
    );
  }

  void _onPointerMove(PointerMoveEvent event) {
    final pos = _toDesktopCoords(event.localPosition);
    widget.backend.sendMouseMove(
      widget.sessionId,
      x: pos.dx.toInt(),
      y: pos.dy.toInt(),
    );
  }

  Offset _toDesktopCoords(Offset localPos) {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return localPos;

    final widgetSize = renderBox.size;
    final scaleX = widget.width / widgetSize.width;
    final scaleY = widget.height / widgetSize.height;

    return Offset(
      (localPos.dx * scaleX).clamp(0, widget.width.toDouble() - 1),
      (localPos.dy * scaleY).clamp(0, widget.height.toDouble() - 1),
    );
  }

  RdpMouseButton _mapMouseButton(int buttons) {
    if (buttons & kSecondaryButton != 0) return RdpMouseButton.right;
    if (buttons & kMiddleMouseButton != 0) return RdpMouseButton.middle;
    return RdpMouseButton.left;
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    final physicalKey = event.physicalKey;
    final hidUsage = physicalKey.usbHidUsage & 0xFFFF;
    final atScancode = _hidToAtScancode(hidUsage);
    if (atScancode == null) return KeyEventResult.ignored;

    final isPressed = event is KeyDownEvent || event is KeyRepeatEvent;
    widget.backend.sendKeyboardInput(
      widget.sessionId,
      scancode: atScancode,
      isPressed: isPressed,
    );
    return KeyEventResult.handled;
  }

  /// Simplified HID to AT scancode mapping for common keys.
  int? _hidToAtScancode(int hidUsage) {
    const mapping = <int, int>{
      // Letters
      0x04: 0x1E, // A
      0x05: 0x30, // B
      0x06: 0x2E, // C
      0x07: 0x20, // D
      0x08: 0x12, // E
      0x09: 0x21, // F
      0x0A: 0x22, // G
      0x0B: 0x23, // H
      0x0C: 0x17, // I
      0x0D: 0x24, // J
      0x0E: 0x25, // K
      0x0F: 0x26, // L
      0x10: 0x32, // M
      0x11: 0x31, // N
      0x12: 0x18, // O
      0x13: 0x19, // P
      0x14: 0x10, // Q
      0x15: 0x13, // R
      0x16: 0x1F, // S
      0x17: 0x14, // T
      0x18: 0x16, // U
      0x19: 0x2F, // V
      0x1A: 0x11, // W
      0x1B: 0x2D, // X
      0x1C: 0x15, // Y
      0x1D: 0x2C, // Z
      // Numbers
      0x1E: 0x02, // 1
      0x1F: 0x03, // 2
      0x20: 0x04, // 3
      0x21: 0x05, // 4
      0x22: 0x06, // 5
      0x23: 0x07, // 6
      0x24: 0x08, // 7
      0x25: 0x09, // 8
      0x26: 0x0A, // 9
      0x27: 0x0B, // 0
      // Control keys
      0x28: 0x1C, // Enter
      0x29: 0x01, // Escape
      0x2A: 0x0E, // Backspace
      0x2B: 0x0F, // Tab
      0x2C: 0x39, // Space
      0x2D: 0x0C, // Minus
      0x2E: 0x0D, // Equal
      0x2F: 0x1A, // Left Bracket
      0x30: 0x1B, // Right Bracket
      0x31: 0x2B, // Backslash
      0x33: 0x27, // Semicolon
      0x34: 0x28, // Quote
      0x35: 0x29, // Grave
      0x36: 0x33, // Comma
      0x37: 0x34, // Period
      0x38: 0x35, // Slash
      0x39: 0x3A, // Caps Lock
      // Function keys
      0x3A: 0x3B, // F1
      0x3B: 0x3C, // F2
      0x3C: 0x3D, // F3
      0x3D: 0x3E, // F4
      0x3E: 0x3F, // F5
      0x3F: 0x40, // F6
      0x40: 0x41, // F7
      0x41: 0x42, // F8
      0x42: 0x43, // F9
      0x43: 0x44, // F10
      0x44: 0x57, // F11
      0x45: 0x58, // F12
      // Navigation
      0x4F: 0x4D, // Right arrow
      0x50: 0x4B, // Left arrow
      0x51: 0x50, // Down arrow
      0x52: 0x48, // Up arrow
      0x49: 0x52, // Insert
      0x4A: 0x47, // Home
      0x4B: 0x49, // Page Up
      0x4C: 0x53, // Delete
      0x4D: 0x4F, // End
      0x4E: 0x51, // Page Down
      // Modifiers
      0xE0: 0x1D, // Left Control
      0xE1: 0x2A, // Left Shift
      0xE2: 0x38, // Left Alt
      0xE4: 0x1D, // Right Control (extended)
      0xE5: 0x36, // Right Shift
      0xE6: 0x38, // Right Alt (extended)
    };
    return mapping[hidUsage];
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _onKeyEvent,
      child: MouseRegion(
        cursor: SystemMouseCursors.precise,
        child: Listener(
          onPointerDown: _onPointerDown,
          onPointerUp: _onPointerUp,
          onPointerHover: _onPointerHover,
          onPointerMove: _onPointerMove,
          child: CustomPaint(
            size: Size(widget.width.toDouble(), widget.height.toDouble()),
            painter: _RdpFramePainter(_currentFrame),
          ),
        ),
      ),
    );
  }
}

class _RdpFramePainter extends CustomPainter {
  _RdpFramePainter(this.image);

  final ui.Image? image;

  @override
  void paint(Canvas canvas, Size size) {
    if (image == null) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width, size.height),
        Paint()..color = const Color(0xFF1E1E1E),
      );
      final textPainter = TextPainter(
        text: const TextSpan(
          text: 'Connecting...',
          style: TextStyle(color: Color(0xFF888888), fontSize: 16),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(
          (size.width - textPainter.width) / 2,
          (size.height - textPainter.height) / 2,
        ),
      );
      return;
    }

    final src = Rect.fromLTWH(
      0,
      0,
      image!.width.toDouble(),
      image!.height.toDouble(),
    );
    final dst = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawImageRect(image!, src, dst, Paint());
  }

  @override
  bool shouldRepaint(_RdpFramePainter oldDelegate) {
    return oldDelegate.image != image;
  }
}
