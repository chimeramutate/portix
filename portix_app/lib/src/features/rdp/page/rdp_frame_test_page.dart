import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Halaman test untuk membuktikan bahwa CustomPaint + drawImageRect
/// bisa mengisi layar penuh tanpa koneksi RDP asli.
///
/// Cara buka: tambahkan route sementara atau panggil langsung dari
/// salah satu tombol di workspace. Tidak perlu diintegrasikan ke flow utama.
class RdpFrameTestPage extends StatefulWidget {
  const RdpFrameTestPage({super.key});

  @override
  State<RdpFrameTestPage> createState() => _RdpFrameTestPageState();
}

class _RdpFrameTestPageState extends State<RdpFrameTestPage> {
  ui.Image? _image;
  String _status = 'Generating test frame...';
  Timer? _timer;
  int _frameCount = 0;

  // Resolusi "desktop" yang kita simulasikan
  static const int kDesktopW = 1280;
  static const int kDesktopH = 800;

  @override
  void initState() {
    super.initState();
    _generateFrame();
    // Update frame setiap 500ms untuk simulasi stream
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _generateFrame();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _image?.dispose();
    super.dispose();
  }

  /// Buat pixel buffer 1280×800 dengan warna yang berubah tiap frame.
  Future<void> _generateFrame() async {
    _frameCount++;
    final buf = Uint8List(kDesktopW * kDesktopH * 4);

    // Background berubah warna tiap frame
    final r = (_frameCount * 30) % 256;
    final g = 100;
    final b = (_frameCount * 15) % 256;

    for (int i = 0; i < kDesktopW * kDesktopH; i++) {
      buf[i * 4 + 0] = r; // R
      buf[i * 4 + 1] = g; // G
      buf[i * 4 + 2] = b; // B
      buf[i * 4 + 3] = 255; // A
    }

    // Gambar grid kotak-kotak supaya mudah lihat proporsi
    _drawGrid(buf, kDesktopW, kDesktopH);

    // Gambar teks info ukuran di pojok
    _drawLabel(buf, kDesktopW, kDesktopH, 'Frame #$_frameCount  ${kDesktopW}x$kDesktopH');

    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      buf,
      kDesktopW,
      kDesktopH,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    final img = await completer.future;

    _image?.dispose();
    if (!mounted) return;
    setState(() {
      _image = img;
      _status = 'Frame #$_frameCount  |  image=${img.width}x${img.height}';
    });
  }

  /// Gambar grid putih setiap 160px horizontal dan 100px vertikal.
  void _drawGrid(Uint8List buf, int w, int h) {
    const gridSpacingX = 160;
    const gridSpacingY = 100;

    // Garis vertikal
    for (int x = 0; x < w; x += gridSpacingX) {
      for (int y = 0; y < h; y++) {
        final idx = (y * w + x) * 4;
        buf[idx] = 255;
        buf[idx + 1] = 255;
        buf[idx + 2] = 255;
        buf[idx + 3] = 255;
      }
    }
    // Garis horizontal
    for (int y = 0; y < h; y += gridSpacingY) {
      for (int x = 0; x < w; x++) {
        final idx = (y * w + x) * 4;
        buf[idx] = 255;
        buf[idx + 1] = 255;
        buf[idx + 2] = 255;
        buf[idx + 3] = 255;
      }
    }

    // Border merah di tepi untuk konfirmasi batas frame
    for (int x = 0; x < w; x++) {
      // Atas
      _setPixel(buf, w, x, 0, 255, 0, 0);
      _setPixel(buf, w, x, 1, 255, 0, 0);
      // Bawah
      _setPixel(buf, w, x, h - 1, 255, 0, 0);
      _setPixel(buf, w, x, h - 2, 255, 0, 0);
    }
    for (int y = 0; y < h; y++) {
      // Kiri
      _setPixel(buf, w, 0, y, 255, 0, 0);
      _setPixel(buf, w, 1, y, 255, 0, 0);
      // Kanan
      _setPixel(buf, w, w - 1, y, 255, 0, 0);
      _setPixel(buf, w, w - 2, y, 255, 0, 0);
    }
  }

  void _setPixel(Uint8List buf, int w, int x, int y, int r, int g, int b) {
    final idx = (y * w + x) * 4;
    if (idx + 3 >= buf.length) return;
    buf[idx] = r;
    buf[idx + 1] = g;
    buf[idx + 2] = b;
    buf[idx + 3] = 255;
  }

  /// Tulis label sederhana sebagai kotak putih di pojok kiri atas.
  void _drawLabel(Uint8List buf, int w, int h, String label) {
    // Gambar kotak putih 300×20 di posisi (10, 10)
    for (int y = 10; y < 30; y++) {
      for (int x = 10; x < 310; x++) {
        _setPixel(buf, w, x, y, 255, 255, 255);
      }
    }
    // Tulis karakter hitam sederhana (dot pattern per karakter)
    for (int i = 0; i < label.length && i < 40; i++) {
      _setPixel(buf, w, 15 + i * 7, 18, 0, 0, 0);
      _setPixel(buf, w, 16 + i * 7, 16, 0, 0, 0);
      _setPixel(buf, w, 17 + i * 7, 18, 0, 0, 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('RDP Frame Render Test'),
        backgroundColor: const Color(0xFF1A2332),
        foregroundColor: Colors.white,
        actions: [
          // Tampilkan info size dari LayoutBuilder
          Builder(
            builder: (ctx) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: Text(
                  _status,
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ),
            ),
          ),
        ],
      ),
      body: _image == null
          ? const Center(child: CircularProgressIndicator())
          : _buildCanvas(),
    );
  }

  Widget _buildCanvas() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;

        // Log ke console setiap frame
        debugPrint(
          '[TEST] paint container=${w.toInt()}x${h.toInt()} '
          'image=${_image!.width}x${_image!.height}',
        );

        return SizedBox(
          width: w,
          height: h,
          child: CustomPaint(
            size: Size(w, h),
            painter: _TestPainter(_image!, w, h),
          ),
        );
      },
    );
  }
}

class _TestPainter extends CustomPainter {
  _TestPainter(this.image, this.targetW, this.targetH);

  final ui.Image image;
  final double targetW;
  final double targetH;

  @override
  void paint(Canvas canvas, Size size) {
    debugPrint(
      '[TEST] painter size=${size.width.toInt()}x${size.height.toInt()} '
      'target=${targetW.toInt()}x${targetH.toInt()}',
    );

    final src = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    final dst = Rect.fromLTWH(0, 0, size.width, size.height);

    canvas.drawImageRect(image, src, dst, Paint()..filterQuality = FilterQuality.medium);

    // Overlay teks info ukuran di layar
    final tp = TextPainter(
      text: TextSpan(
        text: 'canvas=${size.width.toInt()}x${size.height.toInt()}  '
            'image=${image.width}x${image.height}',
        style: TextStyle(
          color: Colors.yellow,
          fontSize: 14,
          background: Paint()..color = Colors.black54,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, const Offset(8, 8));
  }

  @override
  bool shouldRepaint(_TestPainter old) => old.image != image;
}
