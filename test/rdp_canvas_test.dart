import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/connection_manager/rdp_backend.dart';
import 'package:portix/src/connection_manager/rdp_session_models.dart';
import 'package:portix/src/features/rdp_sessions/rdp_canvas.dart';

void main() {
  testWidgets(
    'RdpCanvas requests snapshots when Rust sends signal-only frames',
    (tester) async {
      final frames = StreamController<RdpFrameEvent>.broadcast();
      var requestCount = 0;
      final backend = RdpBackend.test(
        frameStream: frames.stream,
        requestFrameHandler: (_) async {
          requestCount += 1;
          return _solidRgbaFrame(
            width: 4,
            height: 4,
            r: requestCount == 1 ? 255 : 0,
            g: requestCount == 1 ? 0 : 255,
            b: 0,
          );
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 40,
            height: 40,
            child: RdpCanvas(
              sessionId: 'rdp-test',
              width: 4,
              height: 4,
              backend: backend,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));

      expect(requestCount, greaterThanOrEqualTo(1));
      expect(tester.takeException(), isNull);

      frames.add(
        RdpFrameEvent(
          sessionId: 'rdp-test',
          x: 0,
          y: 0,
          width: 4,
          height: 4,
          desktopWidth: 4,
          desktopHeight: 4,
          sequence: 2,
          fullFrame: true,
          data: Uint8List(0),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));

      expect(requestCount, greaterThanOrEqualTo(2));
      expect(tester.takeException(), isNull);

      await frames.close();
    },
  );

  testWidgets(
    'RdpCanvas rejects malformed dirty regions and falls back to snapshot',
    (tester) async {
      final frames = StreamController<RdpFrameEvent>.broadcast();
      var requestCount = 0;
      final backend = RdpBackend.test(
        frameStream: frames.stream,
        requestFrameHandler: (_) async {
          requestCount += 1;
          return _solidRgbaFrame(width: 4, height: 4, r: 0, g: 0, b: 255);
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 40,
            height: 40,
            child: RdpCanvas(
              sessionId: 'rdp-test',
              width: 4,
              height: 4,
              backend: backend,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));

      frames.add(
        RdpFrameEvent(
          sessionId: 'rdp-test',
          x: 3,
          y: 3,
          width: 4,
          height: 4,
          desktopWidth: 4,
          desktopHeight: 4,
          sequence: 3,
          fullFrame: false,
          data: Uint8List(4 * 4 * 4),
        ),
      );
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));

      expect(requestCount, greaterThanOrEqualTo(2));
      expect(tester.takeException(), isNull);

      await frames.close();
    },
  );

  testWidgets('RdpCanvas composites valid dirty regions over snapshots', (
    tester,
  ) async {
    final frames = StreamController<RdpFrameEvent>.broadcast();
    final backend = RdpBackend.test(
      frameStream: frames.stream,
      requestFrameHandler: (_) async {
        return _solidRgbaFrame(width: 4, height: 4, r: 255, g: 255, b: 255);
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 4,
          height: 4,
          child: RdpCanvas(
            sessionId: 'rdp-test',
            width: 4,
            height: 4,
            backend: backend,
          ),
        ),
      ),
    );
    await _pumpDecode(tester);

    final state = tester.state(find.byType(RdpCanvas)) as dynamic;
    expect(state.debugFrameSizeForTest, (4, 4));
    expect(_bufferPixel(state.debugFrameBufferForTest as Uint8List, 4, 0, 0), (
      255,
      255,
      255,
    ));

    frames.add(
      RdpFrameEvent(
        sessionId: 'rdp-test',
        x: 1,
        y: 1,
        width: 2,
        height: 2,
        desktopWidth: 4,
        desktopHeight: 4,
        sequence: 2,
        fullFrame: false,
        data: _solidRgbaFrame(width: 2, height: 2, r: 255, g: 0, b: 0),
      ),
    );
    await _pumpDecode(tester);

    final buffer = state.debugFrameBufferForTest as Uint8List;
    expect(_bufferPixel(buffer, 4, 0, 0), (255, 255, 255));
    expect(_bufferPixel(buffer, 4, 1, 1), (255, 0, 0));
    expect(_bufferPixel(buffer, 4, 2, 2), (255, 0, 0));
    expect(_bufferPixel(buffer, 4, 3, 3), (255, 255, 255));

    await frames.close();
  });
}

Uint8List _solidRgbaFrame({
  required int width,
  required int height,
  required int r,
  required int g,
  required int b,
}) {
  final bytes = Uint8List(width * height * 4);
  for (var i = 0; i < bytes.length; i += 4) {
    bytes[i] = r;
    bytes[i + 1] = g;
    bytes[i + 2] = b;
    bytes[i + 3] = 255;
  }
  return bytes;
}

Future<void> _pumpDecode(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump(const Duration(milliseconds: 250));
}

(int, int, int) _bufferPixel(Uint8List bytes, int width, int x, int y) {
  final offset = (y * width + x) * 4;
  return (bytes[offset], bytes[offset + 1], bytes[offset + 2]);
}
