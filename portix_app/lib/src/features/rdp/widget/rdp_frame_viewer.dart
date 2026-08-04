import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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
  });

  final String sessionId;
  final int desktopWidth;
  final int desktopHeight;
  final VoidCallback? onDisconnect;

  /// Called when the user double-taps the viewer.
  /// Typically used to exit fullscreen mode.
  final VoidCallback? onDoubleTap;

  @override
  State<RdpFrameViewer> createState() => _RdpFrameViewerState();
}

// ================================================================
// FRAME ASSEMBLY
// Reassembles large dirty rects that were split into 256 KB chunks
// by Rust before transmission.
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
    if (chunks.length != chunkCount) return false;
    for (var i = 0; i < chunkCount; i++) {
      if (!chunks.containsKey(i)) return false;
    }
    return true;
  }

  Uint8List buildBytes() {
    if (!isComplete) {
      throw StateError('Frame not complete: ${chunks.length}/$chunkCount');
    }
    // copy: true — we need an independent buffer because the caller
    // may hold it while new chunks for the next frame arrive.
    final builder = BytesBuilder();
    for (var i = 0; i < chunkCount; i++) {
      final chunk = chunks[i];
      if (chunk == null) throw StateError('Missing chunk $i/$chunkCount');
      builder.add(chunk);
    }
    return builder.takeBytes();
  }
}

// ================================================================
// VIEWER STATE
// ================================================================

class _RdpFrameViewerState extends State<RdpFrameViewer>
    with SingleTickerProviderStateMixin {
  StreamSubscription<RdpFrameEvent>? _frameSub;
  StreamSubscription<RdpStatusEvent>? _statusSub;
  StreamSubscription<RdpErrorEvent>? _errorSub;

  // ------------------------------------------------------------------
  // PERSISTENT FRAMEBUFFER
  //
  // One RGBA buffer for the entire negotiated desktop.
  // Dirty rect patches are blitted into this buffer in-place.
  // We never replace it — only mutate it.
  // ------------------------------------------------------------------
  late Uint8List _framebuffer;
  int get _fbWidth => widget.desktopWidth;
  int get _fbHeight => widget.desktopHeight;

  /// The decoded ui.Image built from the current _framebuffer state.
  /// Replaced at most ~60 times per second via the Ticker.
  ui.Image? _image;

  int get _rowBytes => (_fbWidth * 4 + 63) & ~63;

  /// Whether the framebuffer has been modified since the last repaint.
  bool _framebufferDirty = false;

  /// Whether a ui.Image decode is in-flight (decodeImageFromPixels is async).
  bool _isDecoding = false;

  /// Ticker drives the ~60 FPS repaint loop.
  late Ticker _ticker;

  String? _statusMessage;
  bool _isDisconnected = false;

  /// Chunk assembly state, keyed by frame_id.
  final Map<BigInt, _FrameAssembly> _assemblies = {};
  final Map<BigInt, Timer> _assemblyTimers = {};
  static const Duration _assemblyTimeout = Duration(seconds: 3);

  final FocusNode _focusNode = FocusNode();
  int _currentMouseButton = 0;

  /// Drop frames that arrive out of order.
  /// Menggunakan BigInt agar type-safe dengan frame.frameId (u64 → BigInt via FRB).
  BigInt _lastCompletedFrameId = BigInt.from(-1);

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

    _ticker = createTicker(_onTick)..start();

    final svc = sl<RdpBackendService>();

    // ─── TAMBAH LOGGING LANGSUNG DI LISTENER ───
    _frameSub = svc
        .frameStream()
        .where((e) {
          debugPrint(
            '[RDP STREAM FILTER] frame id=${e.frameId} session=${e.sessionId}',
          );
          return e.sessionId == widget.sessionId;
        })
        .listen(
          (frame) {
            debugPrint(
              '[RDP STREAM LISTEN] got frame id=${frame.frameId} size=${frame.width}x${frame.height}',
            );
            _onFrame(frame);
          },
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
    // RGBA: r=0, g=0, b=0, a=255
    for (var i = 0; i < buf.length; i += 4) {
      buf[i] = 0;
      buf[i + 1] = 0;
      buf[i + 2] = 0;
      buf[i + 3] = 255;
    }
  }

  // ================================================================
  // TICKER — ~60 FPS REPAINT GATE
  // ================================================================

  void _onTick(Duration _) {
    if (_isDisconnected || !mounted) {
      debugPrint(
        '[RDP TICKER] tick skipped: disconnected=$_isDisconnected mounted=$mounted',
      );
      return;
    }
    if (!_framebufferDirty || _isDecoding) {
      debugPrint(
        '[RDP TICKER] tick skipped: dirty=$_framebufferDirty decoding=$_isDecoding',
      );
      return;
    }

    debugPrint('[RDP TICKER] encoding framebuffer...');
    _framebufferDirty = false;
    _isDecoding = true;

    final snapshot = Uint8List.fromList(_framebuffer);

    _decodeFramebuffer(snapshot);
  }

  Future<void> _decodeFramebuffer(Uint8List snapshot) async {
    debugPrint(
      '[RDP DECODE] starting decode snapshot.length=${snapshot.length}',
    );

    if (_isDisconnected || !mounted) {
      debugPrint(
        '[RDP DECODE] aborted: disconnected=$_isDisconnected mounted=$mounted',
      );
      _isDecoding = false;
      return;
    }

    ui.Image? image;
    try {
      debugPrint('[RDP DECODE] calling _decodeImage...');
      image = await _decodeImage(snapshot, _fbWidth, _fbHeight);

      debugPrint(
        '[RDP DECODE] image decoded successfully: ${image.width}x${image.height}',
      );

      if (_isDisconnected || !mounted) {
        debugPrint(
          '[RDP DECODE] disposing decoded image (disconnected or unmounted)',
        );
        image.dispose();
        return;
      }

      final old = _image;
      debugPrint('[RDP DECODE] setState with new image');
      setState(() => _image = image);
      old?.dispose();
    } catch (error, st) {
      debugPrint('[RDP DECODE ERROR] $error\n$st');
      image?.dispose();
    } finally {
      _isDecoding = false;

      if (!_isDisconnected && mounted && _framebufferDirty) {
        debugPrint(
          '[RDP DECODE] framebuffer dirty again, scheduling next decode',
        );
        _framebufferDirty = false;
        _isDecoding = true;
        final next = Uint8List.fromList(_framebuffer);
        scheduleMicrotask(() => _decodeFramebuffer(next));
      }
    }
  }

  Future<ui.Image> _decodeImage(Uint8List bytes, int width, int height) async {
    final expectedSize = _rowBytes * height;
    if (bytes.length != expectedSize) {
      throw StateError('Buffer size mismatch');
    }

    final completer = Completer<ui.Image>();

    // Try multiple formats
    final formats = [
      (ui.PixelFormat.bgra8888, "BgrA8888"),
      (ui.PixelFormat.rgba8888, "RgbA8888"),
    ];

    for (final (format, name) in formats) {
      try {
        debugPrint('[RDP DECODE] trying format: $name');
        ui.decodeImageFromPixels(bytes, width, height, format, (
          ui.Image image,
        ) {
          debugPrint('[RDP DECODE] SUCCESS with format: $name');
          completer.complete(image);
        }, rowBytes: _rowBytes);
        return completer.future; // ← Exit setelah first success
      } catch (e) {
        debugPrint('[RDP DECODE] $name failed: $e');
      }
    }

    completer.completeError(StateError('All formats failed'));
    return completer.future;
  }

  // Future<void> _decodeFramebuffer(Uint8List snapshot) async {
  //   // Guard awal — widget sudah dispose sebelum decode dimulai.
  //   if (_isDisconnected || !mounted) {
  //     _isDecoding = false;
  //     return;
  //   }

  //   ui.Image? image;
  //   try {
  //     image = await _decodeImage(snapshot, _fbWidth, _fbHeight);

  //     // Widget bisa sudah dispose SELAMA await di atas berlangsung.
  //     if (_isDisconnected || !mounted) {
  //       image.dispose();
  //       return;
  //     }

  //     final old = _image;
  //     // mounted sudah dicek di atas — setState aman.
  //     setState(() => _image = image);
  //     old?.dispose();
  //   } catch (error, st) {
  //     debugPrint('[RDP DECODE ERROR] $error\n$st');
  //     image?.dispose();
  //   } finally {
  //     _isDecoding = false;

  //     // Jika ada rect baru masuk selama decode, jadwalkan decode
  //     // berikutnya di microtask (bukan Ticker) supaya tidak skip satu
  //     // vsync penuh.
  //     if (!_isDisconnected && mounted && _framebufferDirty) {
  //       _framebufferDirty = false;
  //       _isDecoding = true;
  //       final next = Uint8List.fromList(_framebuffer);
  //       scheduleMicrotask(() => _decodeFramebuffer(next));
  //     }
  //   }
  // }

  // ================================================================
  // BLIT — copy dirty rect into persistent framebuffer
  //
  // Patch data is packed RGBA, no row padding:
  //   byte layout: R G B A R G B A ... (left→right, top→bottom)
  //   stride      = w * 4
  //
  // Framebuffer layout:
  //   stride = _fbWidth * 4
  //
  // ================================================================

  void _blitRect(int x, int y, int w, int h, Uint8List patchData) {
    if (w <= 0 || h <= 0) return;

    final expectedPatchBytes = w * h * 4;
    if (patchData.length != expectedPatchBytes) {
      debugPrint(
        '[RDP BLIT ERROR] patch size mismatch '
        'got=${patchData.length} expected=$expectedPatchBytes',
      );
      return;
    }

    debugPrint('[RDP BLIT] rect x=$x y=$y w=$w h=$h');

    // ─── TEST: DISABLE CLIPPING ───
    // Cek apakah clipping logic yang bikin diagonal garis

    final srcStride = w * 4; // Patch stride (tight-packed)
    final destStride = _rowBytes; // Framebuffer stride
    final copyBytes = w * 4;

    for (var row = 0; row < h; row++) {
      final srcOffset = row * srcStride;
      final dstOffset = (y + row) * destStride + x * 4;

      // Boundary check
      if (srcOffset + copyBytes > patchData.length) {
        debugPrint('[RDP BLIT] row $row: src out of bounds');
        return;
      }
      if (dstOffset + copyBytes > _framebuffer.length) {
        debugPrint('[RDP BLIT] row $row: dst out of bounds');
        return;
      }

      _framebuffer.setRange(
        dstOffset,
        dstOffset + copyBytes,
        patchData,
        srcOffset,
      );
    }

    _framebufferDirty = true;
    debugPrint('[RDP BLIT] done, dirty=true');
  }

  // ================================================================
  // FRAME RECEIVE — chunk assembly
  // ================================================================

  void _onFrame(RdpFrameEvent frame) {
    if (frame.chunkCount == 1) {
      debugPrint(
        '[RDP FRAME SINGLE] id=${frame.frameId} '
        'size=${frame.width}x${frame.height} pos=${frame.x},${frame.y} '
        'data=${frame.data.length}',
      );
    } else {
      debugPrint(
        '[RDP FRAME MULTI] id=${frame.frameId} '
        'chunk=${frame.chunkIndex}/${frame.chunkCount} '
        'size=${frame.width}x${frame.height} '
        'data=${frame.data.length}',
      );
    }

    if (frame.data.isEmpty && frame.chunkCount == 1) {
      debugPrint(
        '[RDP FRAME ERROR] empty data! '
        'id=${frame.frameId} size=${frame.width}x${frame.height}',
      );
      return; // Skip frame kosong
    }

    if (_isDisconnected) {
      debugPrint('[RDP _onFrame] DROPPED: disconnected');
      return;
    }

    final w = frame.width;
    final h = frame.height;

    if (w <= 0 || h <= 0) {
      debugPrint(
        '[RDP FRAME ERROR] invalid size ${w}x$h frame=${frame.frameId}',
      );
      return;
    }

    if (frame.chunkCount == 0) {
      debugPrint('[RDP FRAME ERROR] chunkCount=0 frame=${frame.frameId}');
      return;
    }

    if (frame.chunkIndex >= frame.chunkCount) {
      debugPrint(
        '[RDP FRAME ERROR] invalid chunk frame=${frame.frameId} '
        'chunk=${frame.chunkIndex} count=${frame.chunkCount}',
      );
      return;
    }

    // Single chunk — skip assembly
    if (frame.chunkCount == 1) {
      debugPrint('[RDP _onFrame] SINGLE CHUNK: proceeding to _onCompleteFrame');
      _onCompleteFrame(frame);
      return;
    }

    debugPrint(
      '[RDP _onFrame] MULTI CHUNK: assembly for frame=${frame.frameId}',
    );

    // Multi-chunk assembly
    var assembly = _assemblies[frame.frameId];

    if (assembly == null) {
      debugPrint(
        '[RDP ASSEMBLY] creating new assembly '
        'frame=${frame.frameId} size=${w}x$h chunks=${frame.chunkCount}',
      );
      assembly = _FrameAssembly(
        width: w,
        height: h,
        x: frame.x,
        y: frame.y,
        chunkCount: frame.chunkCount,
      );
      _assemblies[frame.frameId] = assembly;
      _startAssemblyTimeout(frame.frameId);
    }

    if (assembly.width != w ||
        assembly.height != h ||
        assembly.chunkCount != frame.chunkCount ||
        assembly.x != frame.x ||
        assembly.y != frame.y) {
      debugPrint(
        '[RDP ASSEMBLY ERROR] metadata mismatch frame=${frame.frameId}',
      );
      _discardAssembly(frame.frameId);
      return;
    }

    if (assembly.chunks.containsKey(frame.chunkIndex)) {
      debugPrint(
        '[RDP ASSEMBLY] duplicate chunk ignored '
        'frame=${frame.frameId} chunk=${frame.chunkIndex}',
      );
      return;
    }

    assembly.chunks[frame.chunkIndex] = frame.data;
    debugPrint(
      '[RDP ASSEMBLY] chunk received frame=${frame.frameId} '
      'chunk=${frame.chunkIndex}/${frame.chunkCount} '
      'progress=${assembly.chunks.length}/${frame.chunkCount}',
    );

    if (!assembly.isComplete) {
      debugPrint('[RDP ASSEMBLY] not complete yet, waiting for more chunks');
      return;
    }

    debugPrint('[RDP ASSEMBLY] complete, building bytes...');

    Uint8List bytes;
    try {
      bytes = assembly.buildBytes();
    } catch (error, st) {
      debugPrint('[RDP ASSEMBLY BUILD ERROR] $error\n$st');
      _discardAssembly(frame.frameId);
      return;
    }

    final expected = w * h * 4;
    if (bytes.length != expected) {
      debugPrint(
        '[RDP ASSEMBLY SIZE ERROR] frame=${frame.frameId} '
        'bytes=${bytes.length} expected=$expected',
      );
      _discardAssembly(frame.frameId);
      return;
    }

    debugPrint(
      '[RDP ASSEMBLY] assembled complete frame='
      '${frame.frameId} bytes=${bytes.length}',
    );

    final completeFrame = RdpFrameEvent(
      sessionId: frame.sessionId,
      data: bytes,
      width: w,
      height: h,
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
  // COMPLETE FRAME — blit into framebuffer
  // ================================================================

  void _onCompleteFrame(RdpFrameEvent frame) {
    debugPrint(
      '[RDP _onCompleteFrame] ENTRY frame=${frame.frameId} '
      'size=${frame.width}x${frame.height} pos=${frame.x},${frame.y}',
    );

    if (_isDisconnected) {
      debugPrint('[RDP _onCompleteFrame] DROPPED: disconnected');
      return;
    }

    final expected = frame.width * frame.height * 4;
    if (frame.data.length != expected) {
      debugPrint(
        '[RDP FRAME ERROR] frame=${frame.frameId} '
        'bytes=${frame.data.length} expected=$expected '
        'size=${frame.width}x${frame.height}',
      );
      return;
    }

    if (frame.frameId < _lastCompletedFrameId) {
      debugPrint(
        '[RDP FRAME DROP] old frame=${frame.frameId} last=$_lastCompletedFrameId',
      );
      return;
    }
    _lastCompletedFrameId = frame.frameId;

    debugPrint('[RDP _onCompleteFrame] calling _blitRect...');
    _blitRect(frame.x, frame.y, frame.width, frame.height, frame.data);
    debugPrint(
      '[RDP _onCompleteFrame] after _blitRect, dirty=$_framebufferDirty',
    );
  }

  // ================================================================
  // IMAGE DECODER
  //
  // Converts the persistent RGBA framebuffer into a ui.Image using
  // ImageDescriptor.raw (non-deprecated, synchronous-ish path).
  //
  // Why NOT decodeImageFromPixels:
  //   • Deprecated in Flutter 3.x.
  //   • Hardcodes kPremul_SkAlphaType internally — causes a diagonal
  //     shear / stripe artefact in Skia when the internal texture
  //     stride doesn't align with what the GPU driver expects.
  //   • Provides no way to pass explicit rowBytes to the Skia raster
  //     pipeline when the width produces a non-power-of-two stride.
  //
  // Why ImageDescriptor.raw:
  //   • Official replacement, documented as the correct API for raw
  //     pixel buffers.
  //   • rowBytes is passed explicitly and aligned to 4-byte boundary
  //     (width * 4 is already 4-byte aligned for RGBA, but the
  //     alignment formula makes the intent explicit and is safe if
  //     the format ever changes to a different bpp).
  //   • Buffer size is validated before the engine sees it, preventing
  //     silent corruption from an unexpected IronRDP padding byte.
  //   • Single await chain — no callback indirection, easier to reason
  //     about cancellation / lifecycle.
  //
  // NOTE on byte order (IronRDP → Flutter):
  //   IronRDP PixelFormat::RgbA32  →  R[0] G[1] B[2] A[3] in memory.
  //   Flutter  PixelFormat.rgba8888 →  R[0] G[1] B[2] A[3] in memory
  //   (confirmed from engine/src/flutter/lib/ui/painting/
  //    image_descriptor.cc: index 0 → kRGBA_8888_SkColorType).
  //   The formats are identical — no channel swap is required.
  //
  // NOTE on alpha:
  //   Alpha is forced to 0xFF in Rust (emit_frame) before the bytes
  //   reach Dart, so premultiplication is a mathematical no-op.
  // ================================================================

  // Future<ui.Image> _decodeImage(Uint8List bytes, int width, int height) async {
  //   final expectedSize = _rowBytes * height;
  //   final completer = Completer<ui.Image>();

  //   if (bytes.length != expectedSize) {
  //     debugPrint(
  //       '[RDP DECODE ERROR] Buffer size mismatch! '
  //       'Got ${bytes.length} bytes, expected $expectedSize '
  //       'for ${width}x$height (stride=$_rowBytes).',
  //     );
  //     throw StateError('Buffer size mismatch');
  //   }

  //   try {
  //     ui.decodeImageFromPixels(
  //       bytes,
  //       width,
  //       height,
  //       ui.PixelFormat.bgra8888, // ← Sesuai dengan Rust BgrX32
  //       (ui.Image image) {
  //         completer.complete(image);
  //       },
  //       rowBytes: _rowBytes,
  //     );
  //   } catch (e) {
  //     debugPrint('[RDP DECODE EXCEPTION] $e');
  //     completer.completeError(e);
  //   }

  //   return completer.future;
  // }

  // ================================================================
  // ASSEMBLY TIMEOUT
  // ================================================================

  void _startAssemblyTimeout(BigInt frameId) {
    _assemblyTimers[frameId]?.cancel();
    _assemblyTimers[frameId] = Timer(_assemblyTimeout, () {
      if (_assemblies.containsKey(frameId)) {
        debugPrint('[RDP ASSEMBLY TIMEOUT] frame=$frameId');
        _discardAssembly(frameId);
      }
    });
  }

  void _discardAssembly(BigInt frameId) {
    _assemblyTimers.remove(frameId)?.cancel();
    _assemblies.remove(frameId);
  }

  void _clearAllAssemblies() {
    for (final t in _assemblyTimers.values) {
      t.cancel();
    }
    _assemblyTimers.clear();
    _assemblies.clear();
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

    // Cek disconnect/error SEBELUM setState agar tidak setState
    // setelah _handleDisconnect membersihkan state.
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

    // Reset frame ID counter agar reconnect ke session baru tidak men-drop
    // semua frame (Rust selalu mulai dari frame_id=0 untuk setiap session).
    _lastCompletedFrameId = BigInt.from(-1);

    // Stop ticker SEGERA — tidak ada decode baru setelah ini.
    _ticker.stop();
    _clearAllAssemblies();

    // Dispose image segera, bukan di dalam Future.
    final image = _image;
    _image = null;
    image?.dispose();

    // Tunda navigasi 1 detik agar pengguna bisa lihat pesan error.
    // Gunakan addPostFrameCallback supaya tidak ada setState / Navigator
    // call yang terjadi di tengah frame build yang sedang berjalan.
    Future<void>.delayed(const Duration(seconds: 1), () {
      // Cek mounted DALAM closure karena widget bisa sudah di-dispose
      // oleh navigasi lain selama jeda 1 detik.
      if (!mounted) return;
      widget.onDisconnect?.call();
    });
  }

  // ================================================================
  // MOUSE COORDINATE
  //
  // Maps widget-local pointer position to RDP desktop coordinates.
  //
  // The desktop image is stretched to fill the entire widget (no
  // letterboxing), so the mapping is a simple linear scale:
  //   desktop_x = pointer_x / widget_width  * desktop_width
  //   desktop_y = pointer_y / widget_height * desktop_height
  // ================================================================

  (int, int) _toDesktopCoords(Offset pos, Size size) {
    if (size.width <= 0 || size.height <= 0) return (0, 0);

    final normalizedX = (pos.dx / size.width).clamp(0.0, 1.0);
    final normalizedY = (pos.dy / size.height).clamp(0.0, 1.0);

    final x = (normalizedX * _fbWidth).round().clamp(0, _fbWidth - 1);
    final y = (normalizedY * _fbHeight).round().clamp(0, _fbHeight - 1);

    return (x, y);
  }

  // ================================================================
  // MOUSE
  // ================================================================

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

  // ================================================================
  // KEYBOARD
  // ================================================================

  /// Maps a Flutter [PhysicalKeyboardKey] to a PS/2 scan code.
  ///
  /// USB HID page 0x07 (keyboard/keypad) maps 1:1 to PS/2 Set-2 with the
  /// following rule:
  ///   • If usbHidUsage <= 0xFF it fits in one byte (Set-1 / Set-2 base).
  ///   • Extended keys (arrows, Ins, Del, Home, End, PgUp, PgDn, PrintScr,
  ///     Pause, numpad /, numpad Enter) have usbHidUsage values that match
  ///     their HID page-0x07 code and IronRDP accepts them directly.
  ///
  /// The previous implementation masked `& 0xFF` which silently dropped
  /// the high byte for keys with usbHidUsage > 0xFF, breaking every
  /// extended key.  We now pass the full HID usage value (clamped to u16).
  int _mapToScancode(PhysicalKeyboardKey key) {
    // usbHidUsage is already a PS/2-compatible code for HID page 0x07.
    // IronRDP's Scancode::from_u16 accepts these directly.
    return key.usbHidUsage & 0xFFFF;
  }

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
    _ticker.dispose();
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
        // Desktop image — stretched to fill the entire widget area.
        Positioned.fill(child: CustomPaint(painter: _RdpPainter(image))),

        // Input layer — keyboard + mouse + double-tap to exit fullscreen.
        KeyboardListener(
          focusNode: _focusNode,
          autofocus: true,
          onKeyEvent: _handleKey,
          child: GestureDetector(
            onDoubleTap: widget.onDoubleTap,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerMove: _handlePointerMove,
              onPointerDown: _handlePointerDown,
              onPointerUp: _handlePointerUp,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ],
    );
  }
}

// ================================================================
// PAINTER
//
// Stretches the desktop image to fill the entire widget area.
// No letterboxing — the desktop fills every pixel of the screen,
// identical to how mstsc.exe / Remmina behave in fullscreen mode.
//
// Mouse coordinate mapping in _toDesktopCoords uses the same
// stretch ratio so clicks always land on the correct desktop pixel.
// ================================================================

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
