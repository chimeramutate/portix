import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../connection_manager/rdp_backend.dart';
import '../../connection_manager/rdp_session_models.dart';

/// A widget that renders the RDP desktop and handles input events.
/// Composes dirty rectangles from the Rust RDP stream and renders on demand.
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
  static const bool _debug = bool.fromEnvironment(
    'PORTIX_RDP_DEBUG',
    defaultValue: false,
  );
  static const int _targetFps = int.fromEnvironment(
    'PORTIX_RDP_FPS',
    defaultValue: 30,
  );

  ui.Image? _currentFrame;
  StreamSubscription<RdpFrameEvent>? _frameSub;
  StreamSubscription<RdpClipboardEvent>? _clipboardSub;
  Timer? _heartbeatTimer;
  Timer? _snapshotTimer;
  final FocusNode _focusNode = FocusNode();
  Uint8List? _frameBuffer;
  bool _isDecoding = false;
  bool _renderQueued = false;
  bool _snapshotInFlight = false;
  bool _snapshotDirty = true;
  int _frameWidth = 0;
  int _frameHeight = 0;
  int _events = 0;
  int _hits = 0;
  int _emptyFrames = 0;
  int _decodeMs = 0;
  int _decodeCount = 0;
  int _queuedRenders = 0;
  int _streamBytes = 0;
  int _snapshotRequests = 0;
  DateTime _lastDebugLog = DateTime.now();
  bool _controlPressed = false;
  bool _suppressPasteKeyUp = false;

  @visibleForTesting
  Uint8List? get debugFrameBufferForTest =>
      _frameBuffer == null ? null : Uint8List.fromList(_frameBuffer!);

  @visibleForTesting
  (int, int) get debugFrameSizeForTest => (_frameWidth, _frameHeight);

  @override
  void initState() {
    super.initState();
    _frameSub = widget.backend.frameStream.listen(_onFrameEvent);
    _clipboardSub = widget.backend.clipboardStream.listen(_onClipboardEvent);
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_frameBuffer == null) {
        _snapshotDirty = true;
      }
      _maybeLogStats();
    });
    _snapshotTimer = Timer.periodic(_snapshotInterval, (_) {
      if (!mounted || _snapshotInFlight || !_snapshotDirty) return;
      unawaited(_requestSnapshot(reason: 'tick'));
    });
    unawaited(_requestSnapshot(reason: 'initial'));
    _debugLog(
      'stream renderer target=${_targetFps.clamp(15, 60).toInt()}fps '
      'requested=${widget.width}x${widget.height}',
    );
    // Request initial focus
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _frameSub?.cancel();
    _clipboardSub?.cancel();
    _heartbeatTimer?.cancel();
    _snapshotTimer?.cancel();
    _currentFrame?.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onFrameEvent(RdpFrameEvent event) {
    if (!mounted || event.sessionId != widget.sessionId) return;
    _events += 1;
    _streamBytes += event.data.length;

    final desktopWidth = event.desktopWidth == 0
        ? widget.width
        : event.desktopWidth;
    final desktopHeight = event.desktopHeight == 0
        ? widget.height
        : event.desktopHeight;
    _ensureFrameBuffer(desktopWidth, desktopHeight);

    if (event.data.isEmpty) {
      _snapshotDirty = true;
      _maybeLogStats();
      return;
    }

    if (!_applyFrameEvent(event)) {
      _scheduleSnapshot(reason: 'bad-region');
      return;
    }

    _scheduleRender();
    _maybeLogStats();
  }

  void _onClipboardEvent(RdpClipboardEvent event) {
    if (!mounted || event.sessionId != widget.sessionId) return;
    unawaited(Clipboard.setData(ClipboardData(text: event.text)));
  }

  void _ensureFrameBuffer(int width, int height) {
    final expectedLength = width * height * 4;
    if (_frameBuffer?.length == expectedLength &&
        _frameWidth == width &&
        _frameHeight == height) {
      return;
    }

    _frameBuffer = Uint8List(expectedLength);
    _frameWidth = width;
    _frameHeight = height;
    _debugLog('framebuffer allocated ${width}x$height');
  }

  bool _applyFrameEvent(RdpFrameEvent event) {
    final buffer = _frameBuffer;
    if (buffer == null || _frameWidth == 0 || _frameHeight == 0) return false;

    final x = event.x;
    final y = event.y;
    final width = event.width;
    final height = event.height;
    if (x < 0 ||
        y < 0 ||
        width <= 0 ||
        height <= 0 ||
        x + width > _frameWidth ||
        y + height > _frameHeight) {
      return false;
    }

    final rowBytes = width * 4;
    final expectedBytes = rowBytes * height;
    if (event.data.length < expectedBytes) return false;

    if (event.fullFrame &&
        x == 0 &&
        y == 0 &&
        width == _frameWidth &&
        height == _frameHeight &&
        event.data.length == buffer.length) {
      buffer.setAll(0, event.data);
      return true;
    }

    final stride = _frameWidth * 4;
    for (var row = 0; row < height; row++) {
      final srcStart = row * rowBytes;
      final dstStart = (y + row) * stride + x * 4;
      buffer.setRange(dstStart, dstStart + rowBytes, event.data, srcStart);
    }
    return true;
  }

  void _scheduleRender() {
    if (_renderQueued) {
      _queuedRenders += 1;
      return;
    }
    _renderQueued = true;
    WidgetsBinding.instance.scheduleFrameCallback((_) {
      _renderQueued = false;
      unawaited(_decodeCurrentBuffer());
    });
  }

  void _scheduleSnapshot({required String reason}) {
    if (!mounted) return;
    _snapshotDirty = true;
    if (!_snapshotInFlight && _frameBuffer == null) {
      unawaited(_requestSnapshot(reason: reason));
    }
  }

  Duration get _snapshotInterval {
    // Snapshot is a full 800x600/desktop RGBA pull from Rust. When the Rust
    // stream is configured as signal-only, polling it at render FPS floods the
    // bridge and can make artifacts harder to diagnose. Keep UI render fast,
    // but request full snapshots at a safer rate.
    final fps = _targetFps.clamp(8, 12).toInt();
    return Duration(milliseconds: (1000 / fps).round());
  }

  Future<void> _decodeCurrentBuffer() async {
    if (_isDecoding || !mounted) {
      _queuedRenders += 1;
      _renderQueued = true;
      return;
    }

    final source = _frameBuffer;
    if (source == null || _frameWidth == 0 || _frameHeight == 0) return;
    _isDecoding = true;

    try {
      final frameData = Uint8List.fromList(source);

      if (frameData.isEmpty) {
        _emptyFrames += 1;
        _maybeLogStats();
        return;
      }
      _hits += 1;

      // Determine actual dimensions from data
      final expectedSize = _frameWidth * _frameHeight * 4;
      int decodeWidth = _frameWidth;
      int decodeHeight = _frameHeight;

      if (frameData.length != expectedSize && frameData.length > 0) {
        // Frame size doesn't match widget dimensions — recalculate
        final totalPixels = frameData.length ~/ 4;
        final detectedSize = _detectFrameSize(totalPixels);
        if (detectedSize != null) {
          decodeWidth = detectedSize.$1;
          decodeHeight = detectedSize.$2;
        } else {
          // Can't determine dimensions, skip
          debugPrint(
            'RDP: unexpected frame size ${frameData.length}, skipping',
          );
          _maybeLogStats();
          return;
        }
      }

      // Always render - even black frames confirm connection is alive

      if (!mounted) {
        return;
      }

      final decodeWatch = Stopwatch()..start();
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        frameData,
        decodeWidth,
        decodeHeight,
        ui.PixelFormat.rgba8888,
        (image) => completer.complete(image),
      );
      final image = await completer.future;
      decodeWatch.stop();
      _decodeMs += decodeWatch.elapsedMilliseconds;
      _decodeCount += 1;

      if (mounted) {
        setState(() {
          _currentFrame?.dispose();
          _currentFrame = image;
          _frameWidth = decodeWidth;
          _frameHeight = decodeHeight;
        });
      } else {
        image.dispose();
      }
      _maybeLogStats();
    } catch (e) {
      debugPrint('RDP frame decode ERROR: $e');
      if (e.toString().contains('not found') ||
          e.toString().contains('NotFound')) {
        _heartbeatTimer?.cancel();
        debugPrint('RDP: session gone, stopped rendering');
      }
    } finally {
      _isDecoding = false;
      if (_renderQueued) {
        _renderQueued = false;
        _scheduleRender();
      }
    }
  }

  Future<void> _requestSnapshot({required String reason}) async {
    if (!mounted) return;
    if (_snapshotInFlight) {
      _snapshotDirty = true;
      return;
    }

    _snapshotInFlight = true;
    _snapshotDirty = false;
    _snapshotRequests += 1;

    try {
      final frameData = await widget.backend
          .requestFrame(widget.sessionId)
          .timeout(
            const Duration(milliseconds: 1500),
            onTimeout: () => Uint8List(0),
          );
      if (frameData.isEmpty) {
        _emptyFrames += 1;
        _maybeLogStats();
        return;
      }

      final totalPixels = frameData.length ~/ 4;
      final detectedSize = totalPixels == widget.width * widget.height
          ? (widget.width, widget.height)
          : _detectFrameSize(totalPixels);
      if (detectedSize == null) {
        debugPrint('RDP: snapshot $reason unexpected size ${frameData.length}');
        return;
      }

      _ensureFrameBuffer(detectedSize.$1, detectedSize.$2);
      _frameBuffer!.setAll(0, frameData);
      if (reason != 'signal' && reason != 'coalesced') {
        _debugLog('snapshot $reason ${detectedSize.$1}x${detectedSize.$2}');
      }
      _scheduleRender();
      _maybeLogStats();
    } catch (error) {
      debugPrint('RDP snapshot $reason ERROR: $error');
    } finally {
      _snapshotInFlight = false;
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
    final desktopWidth = _frameWidth == 0 ? widget.width : _frameWidth;
    final desktopHeight = _frameHeight == 0 ? widget.height : _frameHeight;
    final scaleX = desktopWidth / widgetSize.width;
    final scaleY = desktopHeight / widgetSize.height;

    return Offset(
      (localPos.dx * scaleX).clamp(0, desktopWidth.toDouble() - 1),
      (localPos.dy * scaleY).clamp(0, desktopHeight.toDouble() - 1),
    );
  }

  (int, int)? _detectFrameSize(int totalPixels) {
    const commonSizes = <(int, int)>[
      (800, 600),
      (1024, 768),
      (1152, 864),
      (1280, 720),
      (1280, 768),
      (1280, 800),
      (1280, 960),
      (1280, 1024),
      (1360, 768),
      (1366, 768),
      (1440, 900),
      (1600, 900),
      (1680, 1050),
      (1920, 1080),
      (1920, 1200),
      (2560, 1440),
    ];

    for (final size in commonSizes) {
      if (size.$1 * size.$2 == totalPixels) return size;
    }
    return null;
  }

  void _maybeLogStats() {
    if (!_debug) return;

    final now = DateTime.now();
    final elapsedMs = now.difference(_lastDebugLog).inMilliseconds;
    if (elapsedMs < 1000) return;

    final seconds = elapsedMs / 1000.0;
    final avgDecode = _decodeCount == 0 ? 0 : _decodeMs / _decodeCount;
    debugPrint(
      'RDP DEBUG ui session=${widget.sessionId} '
      'requested=${widget.width}x${widget.height} '
      'actual=${_frameWidth}x$_frameHeight '
      'events=${(_events / seconds).toStringAsFixed(1)}/s '
      'stream=${(_streamBytes / 1024 / seconds).toStringAsFixed(1)}KB/s '
      'renders=$_hits empty=$_emptyFrames queued=$_queuedRenders '
      'snapshots=$_snapshotRequests decode_avg=${avgDecode.toStringAsFixed(1)}ms',
    );

    _lastDebugLog = now;
    _events = 0;
    _hits = 0;
    _emptyFrames = 0;
    _decodeMs = 0;
    _decodeCount = 0;
    _queuedRenders = 0;
    _streamBytes = 0;
    _snapshotRequests = 0;
  }

  void _debugLog(String message) {
    if (_debug) debugPrint('RDP DEBUG ui $message');
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
    if (hidUsage == 0xE0 || hidUsage == 0xE4) {
      _controlPressed = isPressed;
    }

    if (hidUsage == 0x19 && _controlPressed) {
      if (event is KeyDownEvent) {
        _suppressPasteKeyUp = true;
        unawaited(_pasteLocalClipboard(atScancode));
      } else if (event is KeyUpEvent && _suppressPasteKeyUp) {
        _suppressPasteKeyUp = false;
      }
      return KeyEventResult.handled;
    }

    widget.backend.sendKeyboardInput(
      widget.sessionId,
      scancode: atScancode,
      isPressed: isPressed,
    );
    return KeyEventResult.handled;
  }

  Future<void> _pasteLocalClipboard(int pasteScancode) async {
    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    final text = clipboard?.text;
    if (text == null) return;

    await widget.backend.setClipboardText(widget.sessionId, text);
    // Let cliprdr complete FORMAT_LIST before the remote paste shortcut.
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await widget.backend.sendKeyboardInput(
      widget.sessionId,
      scancode: pasteScancode,
      isPressed: true,
    );
    await widget.backend.sendKeyboardInput(
      widget.sessionId,
      scancode: pasteScancode,
      isPressed: false,
    );
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
