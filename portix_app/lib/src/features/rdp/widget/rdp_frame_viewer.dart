import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:portix/src/core/di/injection.dart';
import 'package:portix/src/features/rdp/service/rdp_backend_service.dart';
import 'package:portix/src/rust_rdp/domain/events.dart';
import 'package:portix/src/rust_rdp/domain/session.dart';

class RdpFrameViewer extends StatefulWidget {
  const RdpFrameViewer({
    super.key,
    required this.sessionId,
    required this.desktopWidth,
    required this.desktopHeight,
    this.onDisconnect,
    this.onDoubleTap,
    this.onSingleTapUp,
  });

  final String sessionId;
  final int desktopWidth;
  final int desktopHeight;
  final VoidCallback? onDisconnect;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onSingleTapUp;

  @override
  State<RdpFrameViewer> createState() => _RdpFrameViewerState();
}

class _RdpFrameViewerState extends State<RdpFrameViewer> {
  StreamSubscription<RdpFrameEvent>? _frameSub;
  StreamSubscription<RdpStatusEvent>? _statusSub;
  StreamSubscription<RdpErrorEvent>? _errorSub;

  // ── Framebuffer ──────────────────────────────────────────────────
  late Uint8List _framebuffer;
  int get _fbWidth => widget.desktopWidth;
  int get _fbHeight => widget.desktopHeight;
  int get _rowBytes => _fbWidth * 4;

  // ── Display ──────────────────────────────────────────────────────
  ui.Image? _image;

  // ── Decode pipeline ──────────────────────────────────────────────
  // Debounce: tunda decode selama 50ms setelah blit terakhir.
  // Ini memastikan burst frame awal (login screen ~44 frame) sudah
  // selesai semua sebelum decode dimulai, sehingga hasil decode
  // mencerminkan keseluruhan framebuffer yang sudah penuh.
  static const _kDecodeDebounce = Duration(milliseconds: 50);
  Timer? _decodeDebounce;
  bool _isDecoding = false;
  int _blitGeneration = 0;

  // ── UI state ─────────────────────────────────────────────────────
  String? _statusMessage;
  bool _isDisconnected = false;

  final FocusNode _focusNode = FocusNode();
  int _currentMouseButton = 0;

  // ================================================================
  // INIT
  // ================================================================

  @override
  void initState() {
    super.initState();
    debugPrint(
      '[RDP VIEWER] init desktop=${widget.desktopWidth}x${widget.desktopHeight}',
    );

    _framebuffer = Uint8List(_rowBytes * _fbHeight);
    _fillBlack(_framebuffer);

    final svc = sl<RdpBackendService>();

    _frameSub = svc
        .frameStream()
        .where((e) => e.sessionId == widget.sessionId)
        .listen(
          _onCompleteFrame,
          onError: (Object error, StackTrace st) {
            debugPrint('[RDP FRAME STREAM ERROR] $error\n$st');
            _handleDisconnect();
          },
        );

    _statusSub = svc
        .statusStream()
        .where((e) => e.sessionId == widget.sessionId)
        .listen(
          _onStatus,
          onError: (Object error, StackTrace st) {
            debugPrint('[RDP STATUS STREAM ERROR] $error\n$st');
            _handleDisconnect();
          },
        );

    _errorSub = svc
        .errorStream()
        .where((e) => e.sessionId == widget.sessionId)
        .listen(
          _onErrorEvent,
          onError: (Object error, StackTrace st) {
            debugPrint('[RDP ERROR STREAM ERROR] $error\n$st');
            _handleDisconnect();
          },
        );
  }

  static void _fillBlack(Uint8List buf) {
    for (var i = 0; i < buf.length; i += 4) {
      buf[i] = 0;
      buf[i + 1] = 0;
      buf[i + 2] = 0;
      buf[i + 3] = 255;
    }
  }

  // ================================================================
  // DECODE — frame pertama langsung, update berikutnya di-debounce
  // ================================================================

  void _requestDecode() {
    // Frame pertama: langsung decode tanpa menunggu debounce
    if (_image == null && !_isDecoding) {
      _decodeDebounce?.cancel();
      _runDecode();
      return;
    }
    // Update berikutnya: debounce untuk batching
    _decodeDebounce?.cancel();
    _decodeDebounce = Timer(_kDecodeDebounce, _runDecode);
  }

  void _runDecode() {
    if (_isDecoding || _isDisconnected || !mounted) return;
    _isDecoding = true;
    final capturedGen = _blitGeneration;
    final snapshot = Uint8List.fromList(_framebuffer);
    _decodeAndDisplay(snapshot, capturedGen);
  }

  Future<void> _decodeAndDisplay(Uint8List snapshot, int capturedGen) async {
    if (_isDisconnected || !mounted) {
      _isDecoding = false;
      return;
    }

    ui.Image? newImage;
    bool needsRedecode = false;

    try {
      newImage = await _createImage(snapshot);

      if (_isDisconnected || !mounted) {
        newImage.dispose();
        newImage = null;
        return;
      }

      if (capturedGen != _blitGeneration) {
        // Ada blit baru selama decode berlangsung — decode ulang segera
        newImage.dispose();
        newImage = null;
        needsRedecode = true;
        return;
      }

      final old = _image;
      setState(() => _image = newImage);
      old?.dispose();
    } catch (e, st) {
      debugPrint('[RDP DECODE ERROR] $e\n$st');
      newImage?.dispose();
      newImage = null;
    } finally {
      _isDecoding = false;
      if ((needsRedecode || capturedGen != _blitGeneration) &&
          !_isDisconnected &&
          mounted) {
        // Blit baru masuk saat decode — langsung decode tanpa debounce
        _runDecode();
      }
    }
  }

  Future<ui.Image> _createImage(Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: _fbWidth,
      height: _fbHeight,
      rowBytes: _rowBytes,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec(
      targetWidth: _fbWidth,
      targetHeight: _fbHeight,
    );
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  // ================================================================
  // BLIT
  // ================================================================

  void _blitRect(int x, int y, int w, int h, Uint8List patch) {
    if (w <= 0 || h <= 0) return;

    final x0 = x.clamp(0, _fbWidth);
    final y0 = y.clamp(0, _fbHeight);
    final x1 = (x + w).clamp(0, _fbWidth);
    final y1 = (y + h).clamp(0, _fbHeight);
    final cw = x1 - x0;
    final ch = y1 - y0;
    if (cw <= 0 || ch <= 0) return;

    final srcRowBytes = w * 4;
    final dstRowBytes = _rowBytes;
    final copyBpr = cw * 4;
    final srcXOff = (x0 - x) * 4;

    for (var row = 0; row < ch; row++) {
      final srcRow = row + (y0 - y);
      final srcOff = srcRow * srcRowBytes + srcXOff;
      final dstOff = (y0 + row) * dstRowBytes + x0 * 4;

      if (srcOff + copyBpr > patch.length) break;
      if (dstOff + copyBpr > _framebuffer.length) break;

      _framebuffer.setRange(dstOff, dstOff + copyBpr, patch, srcOff);
    }

    _blitGeneration++;
  }

  // ================================================================
  // FRAME EVENT
  // ================================================================

  void _onCompleteFrame(RdpFrameEvent frame) {
    if (_isDisconnected) return;

    final expected = frame.width * frame.height * 4;
    if (frame.data.length != expected) {
      debugPrint(
        '[RDP FRAME ERROR] id=${frame.frameId} '
        'got=${frame.data.length} expected=$expected '
        '(${frame.width}x${frame.height})',
      );
      return;
    }

    _blitRect(
      frame.x.toInt(),
      frame.y.toInt(),
      frame.width.toInt(),
      frame.height.toInt(),
      frame.data,
    );

    // Debounced decode: timer di-reset setiap frame baru masuk
    _requestDecode();
  }

  // ================================================================
  // STATUS / ERROR
  // ================================================================

  void _onStatus(RdpStatusEvent event) {
    debugPrint(
      '[RDP STATUS] session=${event.sessionId} '
      'status=${event.status} message=${event.message}',
    );

    if (!mounted) return;

    final isTerminal =
        event.status == RdpConnectionStatus.disconnected ||
        event.status == RdpConnectionStatus.error;

    setState(() {
      _statusMessage = event.message ?? event.status.name;
    });

    if (isTerminal) _handleDisconnect();
  }

  void _onErrorEvent(RdpErrorEvent event) {
    debugPrint(
      '[RDP ERROR EVENT] session=${event.sessionId} '
      'code=${event.code} message=${event.message}',
    );

    if (!mounted) return;

    setState(() {
      _statusMessage = 'Error: ${event.message}';
    });

    _handleDisconnect();
  }

  // ================================================================
  // DISCONNECT
  // ================================================================

  void _handleDisconnect() {
    if (_isDisconnected) return;
    _isDisconnected = true;

    _decodeDebounce?.cancel();

    final image = _image;
    _image = null;
    image?.dispose();

    Future<void>.delayed(const Duration(seconds: 1), () {
      if (!mounted) return;
      widget.onDisconnect?.call();
    });
  }

  // ================================================================
  // MOUSE / KEYBOARD
  // ================================================================

  (int, int) _toDesktopCoords(Offset pos, Size size) {
    if (size.width <= 0 || size.height <= 0) return (0, 0);
    final nx = (pos.dx / size.width).clamp(0.0, 1.0);
    final ny = (pos.dy / size.height).clamp(0.0, 1.0);
    return (
      (nx * _fbWidth).round().clamp(0, _fbWidth - 1),
      (ny * _fbHeight).round().clamp(0, _fbHeight - 1),
    );
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_isDisconnected) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final (x, y) = _toDesktopCoords(event.localPosition, box.size);
    unawaited(sl<RdpBackendService>().sendMouseMove(widget.sessionId, x, y));
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (_isDisconnected) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final (x, y) = _toDesktopCoords(event.localPosition, box.size);

    if ((event.buttons & kPrimaryButton) != 0) {
      _currentMouseButton = 0;
    } else if ((event.buttons & kMiddleMouseButton) != 0) {
      _currentMouseButton = 1;
    } else if ((event.buttons & kSecondaryMouseButton) != 0) {
      _currentMouseButton = 2;
    }

    _focusNode.requestFocus();
    unawaited(
      sl<RdpBackendService>().sendMouseButton(
        widget.sessionId,
        x,
        y,
        _currentMouseButton,
        true,
      ),
    );
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (_isDisconnected) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final (x, y) = _toDesktopCoords(event.localPosition, box.size);
    unawaited(
      sl<RdpBackendService>().sendMouseButton(
        widget.sessionId,
        x,
        y,
        _currentMouseButton,
        false,
      ),
    );
  }

  void _handlePointerSignal(PointerSignalEvent event) {
    if (_isDisconnected) return;
    if (event is! PointerScrollEvent) return;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final (x, y) = _toDesktopCoords(event.localPosition, box.size);

    final scrollUp = event.scrollDelta.dy < 0;
    final button = scrollUp ? 3 : 4;
    unawaited(
      sl<RdpBackendService>()
          .sendMouseButton(widget.sessionId, x, y, button, true)
          .then((_) {
            if (_isDisconnected) return;
            sl<RdpBackendService>().sendMouseButton(
              widget.sessionId,
              x,
              y,
              button,
              false,
            );
          }),
    );
  }

  int _mapToScancode(PhysicalKeyboardKey key) => key.usbHidUsage & 0xFFFF;

  void _handleKey(KeyEvent event) {
    if (_isDisconnected) return;
    final scancode = _mapToScancode(event.physicalKey);
    if (scancode == 0) return;
    final down = event is KeyDownEvent || event is KeyRepeatEvent;
    unawaited(
      sl<RdpBackendService>().sendKeyboardInput(
        widget.sessionId,
        scancode,
        down,
      ),
    );
  }

  // ================================================================
  // DISPOSE
  // ================================================================

  @override
  void dispose() {
    debugPrint('[RDP VIEWER] dispose session=${widget.sessionId}');

    _isDisconnected = true;
    _decodeDebounce?.cancel();

    _frameSub?.cancel();
    _statusSub?.cancel();
    _errorSub?.cancel();

    // JANGAN disconnect di sini — lifecycle session dikelola oleh
    // RdpSessionPage/Bloc. dispose() hanya cleanup widget resources.

    _image?.dispose();
    _image = null;
    _focusNode.dispose();

    super.dispose();
  }

  // ================================================================
  // BUILD
  // ================================================================

  @override
  Widget build(BuildContext context) {
    final image = _image;

    if (image == null) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                color: Colors.white54,
                strokeWidth: 2,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Connecting to remote desktop…',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${widget.desktopWidth} × ${widget.desktopHeight}',
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            ),
            if (_statusMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _statusMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: CustomPaint(painter: _RdpPainter(image))),
        KeyboardListener(
          focusNode: _focusNode,
          autofocus: true,
          onKeyEvent: _handleKey,
          child: GestureDetector(
            onDoubleTap: widget.onDoubleTap,
            onTapUp: widget.onSingleTapUp != null
                ? (_) => widget.onSingleTapUp!()
                : null,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerMove: _handlePointerMove,
              onPointerDown: _handlePointerDown,
              onPointerUp: _handlePointerUp,
              onPointerSignal: _handlePointerSignal,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ],
    );
  }
}

class _RdpPainter extends CustomPainter {
  const _RdpPainter(this.image);

  final ui.Image image;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_RdpPainter old) => old.image != image;
}
