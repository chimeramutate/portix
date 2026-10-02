import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/features/ssh_sessions/widget/remote/terminal_themes.dart';
import 'package:xterm/xterm.dart';

/// Renders a focused terminal after [output] and counts the pixels painted
/// in the cursor color.
Future<int> _cursorColoredPixels(WidgetTester tester, String output) async {
  final terminal = Terminal()..write(output);
  final boundary = GlobalKey();
  await tester.pumpWidget(
    MaterialApp(
      home: RepaintBoundary(
        key: boundary,
        child: SizedBox(
          width: 200,
          height: 60,
          child: TerminalView(
            terminal,
            autofocus: true,
            theme: portixBuiltinTheme,
            textStyle: const TerminalStyle(fontSize: 14),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  final cursor = portixBuiltinTheme.cursor;
  final render =
      boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final bytes = await tester.runAsync(() async {
    final image = await render.toImage();
    return image.toByteData(format: ui.ImageByteFormat.rawRgba);
  });
  var count = 0;
  for (var i = 0; i + 3 < bytes!.lengthInBytes; i += 4) {
    final pixel = Color.fromARGB(
      bytes.getUint8(i + 3),
      bytes.getUint8(i),
      bytes.getUint8(i + 1),
      bytes.getUint8(i + 2),
    );
    if (pixel.toARGB32() == cursor.toARGB32()) count++;
  }
  return count;
}

void main() {
  testWidgets('the character under the block cursor stays visible', (
    tester,
  ) async {
    final onEmptyCell = await _cursorColoredPixels(tester, '');
    // "A", then cursor back onto it.
    final onCharacter = await _cursorColoredPixels(tester, 'A\x1b[1D');

    expect(onEmptyCell, greaterThan(0), reason: 'cursor is drawn');
    expect(
      onCharacter,
      lessThan(onEmptyCell),
      reason: 'the glyph is drawn over the cursor block, not hidden by it',
    );
  });
}
