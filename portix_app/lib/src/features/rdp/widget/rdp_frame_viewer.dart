import 'dart:async';
import 'dart:typed_data';
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
  });

  final String sessionId;
  final int desktopWidth;
  final int desktopHeight;
  final VoidCallback? onDisconnect;

  @override
  State<RdpFrameViewer> createState() => _RdpFrameViewerState();
}

// ================================================================
// FRAME ASSEMBLY
// ================================================================

class _FrameAssembly {
  _FrameAssembly({
    required this.width,
    required this.height,
    required this.x,
    required this.y,
    required this.chunkCount,
  });

  final int width;
  final int height;
  final int x;
  final int y;
  final int chunkCount;

  final Map<int, Uint8List> chunks = {};

  bool get isComplete {
    if (chunks.length != chunkCount) {
      return false;
    }

    for (var i = 0; i < chunkCount; i++) {
      if (!chunks.containsKey(i)) {
        return false;
      }
    }

    return true;
  }

  Uint8List buildBytes() {
    if (!isComplete) {
      throw StateError(
        'Frame belum lengkap: '
        '${chunks.length}/$chunkCount',
      );
    }

    final builder = BytesBuilder(copy: false);

    for (var i = 0; i < chunkCount; i++) {
      final chunk = chunks[i];

      if (chunk == null) {
        throw StateError('Missing chunk $i/$chunkCount');
      }

      builder.add(chunk);
    }

    return builder.takeBytes();
  }
}

// ================================================================
// VIEWER STATE
// ================================================================

class _RdpFrameViewerState extends State<RdpFrameViewer> {
  StreamSubscription<RdpFrameEvent>? _frameSub;
  StreamSubscription<RdpStatusEvent>? _statusSub;
  StreamSubscription<RdpErrorEvent>? _errorSub;

  ui.Image? _image;

  String? _statusMessage;

  bool _isDisconnected = false;

  /// Apakah saat ini sedang decode satu frame.
  bool _isDecoding = false;

  /// Frame terbaru yang menunggu decode.
  ///
  /// Kita sengaja hanya menyimpan SATU frame terbaru.
  RdpFrameEvent? _latestPendingFrame;

  /// Assembly chunk berdasarkan frame_id.
  final Map<BigInt, _FrameAssembly> _assemblies = {};

  /// Timer timeout assembly.
  final Map<BigInt, Timer> _assemblyTimers = {};

  static const Duration _assemblyTimeout = Duration(seconds: 3);

  final FocusNode _focusNode = FocusNode();

  int _currentMouseButton = 0;

  int _lastCompletedFrameId = -1;

  @override
  void initState() {
    super.initState();

    debugPrint(
      '[RDP VIEWER] init '
      'session=${widget.sessionId} '
      'desktop=${widget.desktopWidth}x${widget.desktopHeight}',
    );

    final svc = sl<RdpBackendService>();

    // ------------------------------------------------------------
    // FRAME STREAM
    // ------------------------------------------------------------

    _frameSub = svc
        .frameStream()
        .where((frame) => frame.sessionId == widget.sessionId)
        .listen(
          _onFrame,
          onError: (Object error, StackTrace stackTrace) {
            debugPrint(
              '[RDP FRAME STREAM ERROR] '
              '$error\n$stackTrace',
            );
          },
        );

    // ------------------------------------------------------------
    // STATUS STREAM
    // ------------------------------------------------------------

    _statusSub = svc
        .statusStream()
        .where((event) => event.sessionId == widget.sessionId)
        .listen(
          _onStatus,
          onError: (Object error, StackTrace stackTrace) {
            debugPrint(
              '[RDP STATUS STREAM ERROR] '
              '$error\n$stackTrace',
            );
          },
        );

    // ------------------------------------------------------------
    // ERROR STREAM
    // ------------------------------------------------------------

    _errorSub = svc
        .errorStream()
        .where((event) => event.sessionId == widget.sessionId)
        .listen(
          _onErrorEvent,
          onError: (Object error, StackTrace stackTrace) {
            debugPrint(
              '[RDP ERROR STREAM ERROR] '
              '$error\n$stackTrace',
            );
          },
        );
  }

  // ================================================================
  // FRAME RECEIVE
  // ================================================================

  void _onFrame(RdpFrameEvent frame) {
    if (_isDisconnected) {
      return;
    }

    final width = frame.width;
    final height = frame.height;

    if (width <= 0 || height <= 0) {
      debugPrint(
        '[RDP FRAME ERROR] invalid size '
        '${width}x$height '
        'frame=${frame.frameId}',
      );
      return;
    }

    if (frame.chunkCount == 0) {
      debugPrint(
        '[RDP FRAME ERROR] chunkCount=0 '
        'frame=${frame.frameId}',
      );
      return;
    }

    if (frame.chunkIndex >= frame.chunkCount) {
      debugPrint(
        '[RDP FRAME ERROR] invalid chunk '
        'frame=${frame.frameId} '
        'chunk=${frame.chunkIndex} '
        'count=${frame.chunkCount}',
      );
      return;
    }

    // ------------------------------------------------------------
    // SINGLE CHUNK
    // ------------------------------------------------------------

    if (frame.chunkCount == 1) {
      debugPrint(
        '[RDP FRAME] single chunk '
        'frame=${frame.frameId} '
        'bytes=${frame.data.length}',
      );

      _onCompleteFrame(frame);
      return;
    }

    // ------------------------------------------------------------
    // MULTI CHUNK
    // ------------------------------------------------------------

    var assembly = _assemblies[frame.frameId];

    if (assembly == null) {
      assembly = _FrameAssembly(
        width: width,
        height: height,
        x: frame.x,
        y: frame.y,
        chunkCount: frame.chunkCount,
      );

      _assemblies[frame.frameId] = assembly;

      debugPrint(
        '[RDP ASSEMBLY START] '
        'frame=${frame.frameId} '
        'size=${width}x$height '
        'chunks=${frame.chunkCount}',
      );

      _startAssemblyTimeout(frame.frameId);
    }

    // ------------------------------------------------------------
    // METADATA CHECK
    // ------------------------------------------------------------

    if (assembly.width != width ||
        assembly.height != height ||
        assembly.chunkCount != frame.chunkCount ||
        assembly.x != frame.x ||
        assembly.y != frame.y) {
      debugPrint(
        '[RDP ASSEMBLY ERROR] metadata mismatch '
        'frame=${frame.frameId}',
      );

      _discardAssembly(frame.frameId);
      return;
    }

    // ------------------------------------------------------------
    // DUPLICATE
    // ------------------------------------------------------------

    if (assembly.chunks.containsKey(frame.chunkIndex)) {
      debugPrint(
        '[RDP CHUNK] duplicate '
        'frame=${frame.frameId} '
        'chunk=${frame.chunkIndex}',
      );

      return;
    }

    // ------------------------------------------------------------
    // STORE CHUNK
    // ------------------------------------------------------------

    assembly.chunks[frame.chunkIndex] = frame.data;

    debugPrint(
      '[RDP CHUNK] '
      'frame=${frame.frameId} '
      'chunk=${frame.chunkIndex + 1}/${frame.chunkCount} '
      'received=${assembly.chunks.length}/${assembly.chunkCount} '
      'bytes=${frame.data.length}',
    );

    if (!assembly.isComplete) {
      return;
    }

    // ------------------------------------------------------------
    // COMPLETE
    // ------------------------------------------------------------

    Uint8List bytes;

    try {
      bytes = assembly.buildBytes();
    } catch (error, stackTrace) {
      debugPrint(
        '[RDP ASSEMBLY BUILD ERROR] '
        '$error\n$stackTrace',
      );

      _discardAssembly(frame.frameId);
      return;
    }

    final expectedLength = width * height * 4;

    if (bytes.length != expectedLength) {
      debugPrint(
        '[RDP ASSEMBLY SIZE ERROR] '
        'frame=${frame.frameId} '
        'bytes=${bytes.length} '
        'expected=$expectedLength',
      );

      _discardAssembly(frame.frameId);
      return;
    }

    final completeFrame = RdpFrameEvent(
      sessionId: frame.sessionId,
      data: bytes,
      width: width,
      height: height,
      x: frame.x,
      y: frame.y,
      frameId: frame.frameId,
      chunkIndex: 0,
      chunkCount: 1,
    );

    _discardAssembly(frame.frameId);

    _onCompleteFrame(completeFrame);
  }

  // ================================================================
  // COMPLETE FRAME
  // ================================================================

  void _onCompleteFrame(RdpFrameEvent frame) {
    if (_isDisconnected) {
      return;
    }

    final expectedLength = frame.width * frame.height * 4;

    if (frame.data.length != expectedLength) {
      debugPrint(
        '[RDP FRAME ERROR] '
        'frame=${frame.frameId} '
        'bytes=${frame.data.length} '
        'expected=$expectedLength '
        'size=${frame.width}x${frame.height}',
      );

      return;
    }

    debugPrint(
      '[RDP FRAME COMPLETE] '
      'frame=${frame.frameId} '
      'bytes=${frame.data.length} '
      'expected=$expectedLength '
      'size=${frame.width}x${frame.height} '
      'first=${frame.data.take(16).toList()}',
    );

    // ------------------------------------------------------------
    // IGNORE OLD FRAME
    // ------------------------------------------------------------

    final frameId = frame.frameId.toInt();

    if (frameId <= _lastCompletedFrameId) {
      debugPrint(
        '[RDP FRAME DROP] old frame '
        'frame=$frameId '
        'last=$_lastCompletedFrameId',
      );

      return;
    }

    _lastCompletedFrameId = frameId;

    // ------------------------------------------------------------
    // ONLY KEEP LATEST
    // ------------------------------------------------------------

    _latestPendingFrame = frame;

    _startDecodeIfNeeded();
  }

  // ================================================================
  // DECODE
  // ================================================================

  void _startDecodeIfNeeded() {
    if (_isDisconnected) {
      return;
    }

    if (_isDecoding) {
      return;
    }

    final frame = _latestPendingFrame;

    if (frame == null) {
      return;
    }

    _latestPendingFrame = null;

    _decodeFrame(frame);
  }

  Future<void> _decodeFrame(RdpFrameEvent frame) async {
    if (_isDisconnected) {
      return;
    }

    _isDecoding = true;

    final stopwatch = Stopwatch()..start();

    debugPrint(
      '[RDP DECODE START] '
      'frame=${frame.frameId} '
      'size=${frame.width}x${frame.height} '
      'bytes=${frame.data.length}',
    );

    try {
      final image = await _decodeImage(frame.data, frame.width, frame.height);

      stopwatch.stop();

      if (_isDisconnected || !mounted) {
        image.dispose();
        return;
      }

      debugPrint(
        '[RDP DECODE COMPLETE] '
        'frame=${frame.frameId} '
        'decode=${stopwatch.elapsedMilliseconds}ms '
        'image=${image.width}x${image.height}',
      );

      // ----------------------------------------------------------
      // FRAME BARU MUNGKIN SUDAH MENUNGGU
      // ----------------------------------------------------------

      final newerFrame = _latestPendingFrame;

      if (newerFrame != null && newerFrame.frameId > frame.frameId) {
        debugPrint(
          '[RDP DECODE] '
          'frame=${frame.frameId} '
          'decoded but newer frame '
          '${newerFrame.frameId} already waiting',
        );
      }

      // ----------------------------------------------------------
      // REPLACE IMAGE
      // ----------------------------------------------------------

      final oldImage = _image;

      if (!mounted || _isDisconnected) {
        image.dispose();
        return;
      }

      debugPrint(
        '[RDP IMAGE SET] '
        'frame=${frame.frameId} '
        'image=${image.width}x${image.height}',
      );

      setState(() {
        _image = image;
      });

      debugPrint(
        '[RDP IMAGE SET DONE] '
        'frame=${frame.frameId}',
      );

      // ----------------------------------------------------------
      // DISPOSE OLD IMAGE
      // ----------------------------------------------------------

      oldImage?.dispose();
    } catch (error, stackTrace) {
      stopwatch.stop();

      debugPrint(
        '[RDP DECODE ERROR] '
        'frame=${frame.frameId} '
        'after=${stopwatch.elapsedMilliseconds}ms '
        '$error\n$stackTrace',
      );
    } finally {
      _isDecoding = false;

      // ----------------------------------------------------------
      // PROCESS NEWEST FRAME
      // ----------------------------------------------------------

      if (!_isDisconnected && mounted && _latestPendingFrame != null) {
        scheduleMicrotask(_startDecodeIfNeeded);
      }
    }
  }

  // ================================================================
  // IMAGE DECODER
  // ================================================================

  Future<ui.Image> _decodeImage(Uint8List bytes, int width, int height) {
    final completer = Completer<ui.Image>();

    try {
      ui.decodeImageFromPixels(bytes, width, height, ui.PixelFormat.rgba8888, (
        ui.Image image,
      ) {
        if (!completer.isCompleted) {
          completer.complete(image);
        }
      }, rowBytes: width * 4);
    } catch (error, stackTrace) {
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
    }

    return completer.future;
  }

  // ================================================================
  // ASSEMBLY TIMEOUT
  // ================================================================

  void _startAssemblyTimeout(BigInt frameId) {
    _assemblyTimers[frameId]?.cancel();

    _assemblyTimers[frameId] = Timer(_assemblyTimeout, () {
      if (_assemblies.containsKey(frameId)) {
        debugPrint(
          '[RDP ASSEMBLY TIMEOUT] '
          'frame=$frameId',
        );

        _discardAssembly(frameId);
      }
    });
  }

  void _discardAssembly(BigInt frameId) {
    _assemblyTimers.remove(frameId)?.cancel();
    _assemblies.remove(frameId);
  }

  void _clearAllAssemblies() {
    for (final timer in _assemblyTimers.values) {
      timer.cancel();
    }

    _assemblyTimers.clear();
    _assemblies.clear();
  }

  // ================================================================
  // STATUS
  // ================================================================

  void _onStatus(RdpStatusEvent event) {
    debugPrint(
      '[RDP STATUS] '
      'session=${event.sessionId} '
      'status=${event.status} '
      'message=${event.message}',
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _statusMessage = event.message ?? event.status.name;
    });

    if (event.status == RdpConnectionStatus.disconnected ||
        event.status == RdpConnectionStatus.error) {
      _handleDisconnect();
    }
  }

  // ================================================================
  // ERROR
  // ================================================================

  void _onErrorEvent(RdpErrorEvent event) {
    debugPrint(
      '[RDP ERROR EVENT] '
      'session=${event.sessionId} '
      'code=${event.code} '
      'message=${event.message}',
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _statusMessage = 'Error: ${event.message}';
    });

    _handleDisconnect();
  }

  // ================================================================
  // DISCONNECT
  // ================================================================

  void _handleDisconnect() {
    if (_isDisconnected) {
      return;
    }

    _isDisconnected = true;

    _latestPendingFrame = null;

    _clearAllAssemblies();

    final image = _image;
    _image = null;

    image?.dispose();

    Future<void>.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        widget.onDisconnect?.call();
      }
    });
  }

  // ================================================================
  // MOUSE COORDINATE
  // ================================================================

  (int, int) _toDesktopCoords(Offset pos, Size size) {
    final image = _image;

    if (image == null || size.width <= 0 || size.height <= 0) {
      return (0, 0);
    }

    final imageRatio = image.width / image.height;

    final widgetRatio = size.width / size.height;

    double imageWidth;
    double imageHeight;
    double offsetX;
    double offsetY;

    if (widgetRatio > imageRatio) {
      imageHeight = size.height;
      imageWidth = imageHeight * imageRatio;

      offsetX = (size.width - imageWidth) / 2;

      offsetY = 0;
    } else {
      imageWidth = size.width;
      imageHeight = imageWidth / imageRatio;

      offsetX = 0;

      offsetY = (size.height - imageHeight) / 2;
    }

    final localX = pos.dx - offsetX;

    final localY = pos.dy - offsetY;

    final normalizedX = (localX / imageWidth).clamp(0.0, 1.0);

    final normalizedY = (localY / imageHeight).clamp(0.0, 1.0);

    final x = (normalizedX * image.width).round().clamp(0, image.width - 1);

    final y = (normalizedY * image.height).round().clamp(0, image.height - 1);

    return (x, y);
  }

  // ================================================================
  // MOUSE
  // ================================================================

  void _handlePointerMove(PointerMoveEvent event) {
    if (_isDisconnected) {
      return;
    }

    final box = context.findRenderObject() as RenderBox?;

    if (box == null) {
      return;
    }

    final (x, y) = _toDesktopCoords(event.localPosition, box.size);

    unawaited(sl<RdpBackendService>().sendMouseMove(widget.sessionId, x, y));
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (_isDisconnected) {
      return;
    }

    final box = context.findRenderObject() as RenderBox?;

    if (box == null) {
      return;
    }

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
    if (_isDisconnected) {
      return;
    }

    final box = context.findRenderObject() as RenderBox?;

    if (box == null) {
      return;
    }

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

  // ================================================================
  // KEYBOARD
  // ================================================================

  int _mapToPs2Scancode(PhysicalKeyboardKey key) {
    return key.usbHidUsage & 0xFF;
  }

  void _handleKey(KeyEvent event) {
    if (_isDisconnected) {
      return;
    }

    final scancode = _mapToPs2Scancode(event.physicalKey);

    if (scancode == 0) {
      return;
    }

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
    debugPrint(
      '[RDP VIEWER] dispose '
      'session=${widget.sessionId}',
    );

    _isDisconnected = true;

    _latestPendingFrame = null;

    _clearAllAssemblies();

    _frameSub?.cancel();
    _statusSub?.cancel();
    _errorSub?.cancel();

    unawaited(sl<RdpBackendService>().disconnect(widget.sessionId));

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

    debugPrint(
      '[RDP BUILD] '
      'session=${widget.sessionId} '
      'hasImage=${image != null} '
      'imageSize=${image?.width}x${image?.height}',
    );

    if (image == null) {
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
                textAlign: TextAlign.center,
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
        Positioned.fill(child: CustomPaint(painter: _RdpPainter(image))),

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

// ================================================================
// PAINTER
// ================================================================

class _RdpPainter extends CustomPainter {
  const _RdpPainter(this.image);

  final ui.Image image;

  @override
  void paint(Canvas canvas, Size size) {
    debugPrint(
      '[RDP PAINT] '
      'image=${image.width}x${image.height} '
      'canvas=${size.width}x${size.height}',
    );

    if (size.width <= 0 || size.height <= 0) {
      return;
    }

    final imageRatio = image.width / image.height;

    final widgetRatio = size.width / size.height;

    Rect dstRect;

    if (widgetRatio > imageRatio) {
      final scaledHeight = size.height;

      final scaledWidth = scaledHeight * imageRatio;

      final dx = (size.width - scaledWidth) / 2;

      dstRect = Rect.fromLTWH(dx, 0, scaledWidth, scaledHeight);
    } else {
      final scaledWidth = size.width;

      final scaledHeight = scaledWidth / imageRatio;

      final dy = (size.height - scaledHeight) / 2;

      dstRect = Rect.fromLTWH(0, dy, scaledWidth, scaledHeight);
    }

    final paint = Paint()..filterQuality = FilterQuality.none;

    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      dstRect,
      paint,
    );
  }

  @override
  bool shouldRepaint(_RdpPainter oldDelegate) {
    final repaint = oldDelegate.image != image;

    debugPrint('[RDP PAINTER] shouldRepaint=$repaint');

    return repaint;
  }
}
