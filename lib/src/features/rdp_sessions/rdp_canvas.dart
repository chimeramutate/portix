import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../connection_manager/rdp_backend.dart';
import '../../connection_manager/rdp_session_models.dart';

/// A widget that renders the RDP desktop and handles input events.
/// Uses frame polling instead of streaming for performance.
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
  Timer? _pollTimer;
  final FocusNode _focusNode = FocusNode();
  bool _isPolling = false;

  @override
  void initState() {
    super.initState();
    // Delay polling start to give Rust backend time to complete RDP handshake
    Future.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      // Poll frames at ~15 FPS — balanced between smoothness and CPU usage
      _pollTimer = Timer.periodic(
        const Duration(milliseconds: 66),
        (_) => _pollFrame(),
      );
    });
    // Request initial focus
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _currentFrame?.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _pollFrame() async {
    if (_isPolling || !mounted) return;
    _isPolling = true;

    try {
      final frameData = await widget.backend.requestFrame(widget.sessionId);

      if (frameData.isEmpty) {
        _isPolling = false;
        return;
      }

      // Determine actual dimensions from data
      final expectedSize = widget.width * widget.height * 4;
      int decodeWidth = widget.width;
      int decodeHeight = widget.height;

      if (frameData.length != expectedSize && frameData.length > 0) {
        // Frame size doesn't match widget dimensions — recalculate
        final totalPixels = frameData.length ~/ 4;
        // Try common aspect ratios
        if (totalPixels == 1920 * 1080) {
          decodeWidth = 1920;
          decodeHeight = 1080;
        } else if (totalPixels == 1024 * 768) {
          decodeWidth = 1024;
          decodeHeight = 768;
        } else if (totalPixels == 1280 * 720) {
          decodeWidth = 1280;
          decodeHeight = 720;
        } else {
          // Can't determine dimensions, skip
          debugPrint(
            'RDP: unexpected frame size ${frameData.length}, skipping',
          );
          _isPolling = false;
          return;
        }
      }

      // Check if frame has any non-zero content
      bool hasContent = false;
      for (int i = 0; i < frameData.length; i += 64) {
        if (frameData[i] != 0) {
          hasContent = true;
          break;
        }
      }
      // Always render - even black frames confirm connection is alive

      if (!mounted) {
        _isPolling = false;
        return;
      }

      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        frameData,
        decodeWidth,
        decodeHeight,
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
    } catch (e) {
      debugPrint('RDP frame poll ERROR: $e');
      if (e.toString().contains('not found') ||
          e.toString().contains('NotFound')) {
        _pollTimer?.cancel();
        debugPrint('RDP: session gone, stopped polling');
      }
    } finally {
      _isPolling = false;
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

  int? _hidToAtScancode(int hidUsage) {
    const mapping = <int, int>{
      0x04: 0x1E, 0x05: 0x30, 0x06: 0x2E, 0x07: 0x20, 0x08: 0x12,
      0x09: 0x21, 0x0A: 0x22, 0x0B: 0x23, 0x0C: 0x17, 0x0D: 0x24,
      0x0E: 0x25, 0x0F: 0x26, 0x10: 0x32, 0x11: 0x31, 0x12: 0x18,
      0x13: 0x19, 0x14: 0x10, 0x15: 0x13, 0x16: 0x1F, 0x17: 0x14,
      0x18: 0x16, 0x19: 0x2F, 0x1A: 0x11, 0x1B: 0x2D, 0x1C: 0x15,
      0x1D: 0x2C, // A-Z
      0x1E: 0x02, 0x1F: 0x03, 0x20: 0x04, 0x21: 0x05, 0x22: 0x06,
      0x23: 0x07, 0x24: 0x08, 0x25: 0x09, 0x26: 0x0A, 0x27: 0x0B, // 1-0
      0x28: 0x1C,
      0x29: 0x01,
      0x2A: 0x0E,
      0x2B: 0x0F,
      0x2C: 0x39, // Enter,Esc,BS,Tab,Space
      0x2D: 0x0C, 0x2E: 0x0D, 0x2F: 0x1A, 0x30: 0x1B, 0x31: 0x2B,
      0x33: 0x27, 0x34: 0x28, 0x35: 0x29, 0x36: 0x33, 0x37: 0x34, 0x38: 0x35,
      0x39: 0x3A, // Caps
      0x3A: 0x3B, 0x3B: 0x3C, 0x3C: 0x3D, 0x3D: 0x3E, 0x3E: 0x3F,
      0x3F: 0x40, 0x40: 0x41, 0x41: 0x42, 0x42: 0x43, 0x43: 0x44,
      0x44: 0x57, 0x45: 0x58, // F1-F12
      0x4F: 0x4D, 0x50: 0x4B, 0x51: 0x50, 0x52: 0x48, // Arrows
      0x49: 0x52, 0x4A: 0x47, 0x4B: 0x49, 0x4C: 0x53, 0x4D: 0x4F, 0x4E: 0x51,
      0xE0: 0x1D, 0xE1: 0x2A, 0xE2: 0x38, // LCtrl,LShift,LAlt
      0xE4: 0x1D, 0xE5: 0x36, 0xE6: 0x38, // RCtrl,RShift,RAlt
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SizedBox(
                width: constraints.maxWidth,
                height: constraints.maxHeight,
                child: CustomPaint(
                  painter: _RdpFramePainter(_currentFrame),
                  size: Size(constraints.maxWidth, constraints.maxHeight),
                ),
              );
            },
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
          text: 'Waiting for desktop...',
          style: TextStyle(color: Color(0xFF888888), fontSize: 14),
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
    // Fill the entire widget area — resolution is matched to window size
    final dst = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawImageRect(
      image!,
      src,
      dst,
      Paint()..filterQuality = FilterQuality.low,
    );
  }

  @override
  bool shouldRepaint(_RdpFramePainter oldDelegate) {
    return oldDelegate.image != image;
  }
}
