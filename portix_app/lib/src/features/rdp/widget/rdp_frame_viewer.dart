import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:portix/src/core/di/injection.dart';
import 'package:portix/src/features/rdp/service/rdp_backend_service.dart';

class RdpFrameViewer extends StatefulWidget {
  const RdpFrameViewer({
    super.key,
    required this.sessionId,
    required this.desktopWidth,
    required this.desktopHeight,
  });

  final String sessionId;
  final int desktopWidth;
  final int desktopHeight;

  @override
  State<RdpFrameViewer> createState() => _RdpFrameViewerState();
}

class _RdpFrameViewerState extends State<RdpFrameViewer> {
  StreamSubscription<RdpFrameEvent>? _frameSub;
  StreamSubscription<RdpStatusEvent>? _statusSub;
  StreamSubscription<RdpErrorEvent>? _errorSub;

  /// Full-resolution BGRA pixel buffer (bufferWidth * bufferHeight * 4 bytes).
  /// Tiles di-blit langsung ke sini, lalu di-decode ke ui.Image sekali per frame.
  Uint8List _pixelBuffer = Uint8List(0);
  int _bufferWidth = 0;
  int _bufferHeight = 0;

  /// Antrian tile yang belum di-render. Semua tile di-blit ke buffer
  /// terlebih dahulu, baru satu kali decode ke ui.Image per animation frame.
  final List<RdpFrameEvent> _pendingTiles = [];
  bool _renderScheduled = false;

  ui.Image? _image;
  String? _statusMessage;

  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Inisialisasi buffer dengan warna biru gelap (dark navy seperti xrdp background)
    _resetBuffer(widget.desktopWidth, widget.desktopHeight);

    final svc = sl<RdpBackendService>();
    _frameSub = svc
        .frameStream()
        .where((f) => f.sessionId == widget.sessionId)
        .listen(_onFrame);
    _statusSub = svc
        .statusStream()
        .where((event) => event.sessionId == widget.sessionId)
        .listen(_onStatus);
    _errorSub = svc
        .errorStream()
        .where((event) => event.sessionId == widget.sessionId)
        .listen(_onErrorEvent);
  }

  /// Init buffer dengan warna background default (solid black BGRA: 0,0,0,255)
  void _resetBuffer(int w, int h) {
    _bufferWidth = w > 0 ? w : 1280;
    _bufferHeight = h > 0 ? h : 800;
    final size = _bufferWidth * _bufferHeight * 4;
    _pixelBuffer = Uint8List(size);
    // Fill alpha=255 agar tidak transparent
    for (int i = 3; i < size; i += 4) {
      _pixelBuffer[i] = 255;
    }
  }

  /// Terima tile, masukkan ke antrian, jadwalkan render di frame berikutnya.
  /// Dengan pendekatan ini, semua tile yang datang dalam satu "burst" di-blit
  /// bersama sebelum satu decode → mengurangi total decode calls secara drastis.
  void _onFrame(RdpFrameEvent frame) {
    if (frame.width == 0 || frame.height == 0) return;
    if (frame.data.isEmpty) return;

    debugPrint(
      '[RDP] tile: x=${frame.x} y=${frame.y} w=${frame.width} h=${frame.height}'
      ' bytes=${frame.data.length} expected=${frame.width * frame.height * 4}',
    );

    _pendingTiles.add(frame);

    if (!_renderScheduled) {
      _renderScheduled = true;
      // Jadwalkan render setelah microtask queue selesai (batching tiles)
      Future.microtask(_flushTiles);
    }
  }

  Future<void> _flushTiles() async {
    if (!mounted) {
      _pendingTiles.clear();
      _renderScheduled = false;
      return;
    }

    // Ambil semua tile yang pending
    final tiles = List<RdpFrameEvent>.from(_pendingTiles);
    _pendingTiles.clear();
    _renderScheduled = false;

    if (tiles.isEmpty) return;

    try {
      // Blit semua tiles ke pixel buffer
      for (final tile in tiles) {
        _blitTile(tile);
      }

      // Satu kali decode untuk semua tiles yang sudah di-blit
      final newImage = await _decodePixelBuffer(
        _pixelBuffer,
        _bufferWidth,
        _bufferHeight,
      );

      if (!mounted) {
        newImage.dispose();
        return;
      }

      final oldImage = _image;
      setState(() => _image = newImage);
      oldImage?.dispose();
    } catch (error, stackTrace) {
      debugPrint('RDP flush error: $error\n$stackTrace');
    }
  }

  /// Blit satu tile ke dalam pixel buffer di posisi (tile.x, tile.y).
  void _blitTile(RdpFrameEvent tile) {
    final tileX = tile.x;
    final tileY = tile.y;
    final tileW = tile.width;
    final tileH = tile.height;
    final tileData = tile.data;

    // Jika tile melebihi buffer, perbesar buffer sambil mempertahankan konten lama
    if (tileX + tileW > _bufferWidth || tileY + tileH > _bufferHeight) {
      final newW =
          (tileX + tileW > _bufferWidth) ? (tileX + tileW) : _bufferWidth;
      final newH =
          (tileY + tileH > _bufferHeight) ? (tileY + tileH) : _bufferHeight;

      final newBuf = Uint8List(newW * newH * 4);
      // Fill alpha=255
      for (int i = 3; i < newBuf.length; i += 4) {
        newBuf[i] = 255;
      }
      // Salin konten lama baris per baris
      for (int row = 0; row < _bufferHeight; row++) {
        final srcStart = row * _bufferWidth * 4;
        final dstStart = row * newW * 4;
        final rowLen = _bufferWidth * 4;
        newBuf.setRange(dstStart, dstStart + rowLen, _pixelBuffer, srcStart);
      }
      _pixelBuffer = newBuf;
      _bufferWidth = newW;
      _bufferHeight = newH;
    }

    // Validasi ukuran data tile
    final expectedBytes = tileW * tileH * 4;
    if (tileData.length < expectedBytes) {
      debugPrint(
          'RDP tile size mismatch: got ${tileData.length}, expected $expectedBytes');
      return;
    }

    // Blit baris per baris dari tile ke buffer
    for (int row = 0; row < tileH; row++) {
      final dstRow = tileY + row;
      if (dstRow >= _bufferHeight) break; // Jangan tulis di luar buffer

      final dstOffset = (dstRow * _bufferWidth + tileX) * 4;
      final srcOffset = row * tileW * 4;
      final rowBytes = tileW * 4;

      if (dstOffset + rowBytes > _pixelBuffer.length) break;

      _pixelBuffer.setRange(
        dstOffset,
        dstOffset + rowBytes,
        tileData,
        srcOffset,
      );
    }
  }

  void _onStatus(RdpStatusEvent event) {
    if (!mounted) return;
    setState(() => _statusMessage = event.message ?? event.status.name);
  }

  void _onErrorEvent(RdpErrorEvent event) {
    if (!mounted) return;
    setState(() => _statusMessage = 'Error: ${event.message}');
  }

  @override
  void dispose() {
    _frameSub?.cancel();
    _statusSub?.cancel();
    _errorSub?.cancel();
    _image?.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  (int, int) _toDesktopCoords(Offset pos, Size size) {
    final dx = (pos.dx * _bufferWidth / size.width).round().clamp(
      0,
      _bufferWidth - 1,
    );
    final dy = (pos.dy * _bufferHeight / size.height).round().clamp(
      0,
      _bufferHeight - 1,
    );
    return (dx, dy);
  }

  void _handlePointerMove(PointerMoveEvent e) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final (x, y) = _toDesktopCoords(e.localPosition, box.size);
    sl<RdpBackendService>().sendMouseMove(widget.sessionId, x, y);
  }

  void _handlePointerDown(PointerDownEvent e) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final (x, y) = _toDesktopCoords(e.localPosition, box.size);

    int btn = 0;
    if (e.buttons & kPrimaryButton != 0) {
      btn = 0;
    } else if (e.buttons & kMiddleMouseButton != 0) {
      btn = 1;
    } else if (e.buttons & kSecondaryButton != 0) {
      btn = 2;
    }

    _focusNode.requestFocus();
    sl<RdpBackendService>().sendMouseButton(widget.sessionId, x, y, btn, true);
  }

  void _handlePointerUp(PointerUpEvent e) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final (x, y) = _toDesktopCoords(e.localPosition, box.size);

    int btn = 0;
    if (e.buttons & kPrimaryButton != 0) {
      btn = 0;
    } else if (e.buttons & kMiddleMouseButton != 0) {
      btn = 1;
    } else if (e.buttons & kSecondaryButton != 0) {
      btn = 2;
    }

    sl<RdpBackendService>().sendMouseButton(widget.sessionId, x, y, btn, false);
  }

  int _mapToPs2Scancode(PhysicalKeyboardKey key) {
    return key.usbHidUsage & 0xFF;
  }

  void _handleKey(KeyEvent event) {
    final scancode = _mapToPs2Scancode(event.physicalKey);
    if (scancode == 0) return;
    final down = event is KeyDownEvent || event is KeyRepeatEvent;
    sl<RdpBackendService>().sendKeyboardInput(widget.sessionId, scancode, down);
  }

  @override
  Widget build(BuildContext context) {
    if (_image == null) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 16),
            const Text(
              'Waiting for frame...',
              style: TextStyle(color: Colors.white70),
            ),
            if (_statusMessage != null) ...[
              const SizedBox(height: 10),
              Text(
                _statusMessage!,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ],
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: CustomPaint(painter: _RdpPainter(_image!))),
        KeyboardListener(
          focusNode: _focusNode,
          autofocus: true,
          onKeyEvent: _handleKey,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerMove: _handlePointerMove,
            onPointerDown: _handlePointerDown,
            onPointerUp: _handlePointerUp,
            child: const SizedBox.expand(),
          ),
        ),
      ],
    );
  }
}

/// Decode pixel buffer ke ui.Image.
/// IronRDP PixelFormat::RgbA32 ternyata menyimpan byte dalam urutan B,G,R,A
/// (terkonfirmasi dari warna: dengan bgra8888 warna xrdp logo benar).
/// Flutter ui.PixelFormat.bgra8888 = byte[0]=B, [1]=G, [2]=R, [3]=A ✓
Future<ui.Image> _decodePixelBuffer(
  Uint8List pixels,
  int width,
  int height,
) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    pixels,
    width,
    height,
    ui.PixelFormat.bgra8888, // Confirmed: IronRDP byte order is BGRA
    completer.complete,
  );
  return completer.future;
}

class _RdpPainter extends CustomPainter {
  _RdpPainter(this.image);
  final ui.Image image;

  @override
  void paint(Canvas canvas, Size size) {
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
