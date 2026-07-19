import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/src/utils/circular_buffer.dart';
import 'package:xterm/xterm.dart';

String _terminalDebugSnapshot(Terminal terminal) {
  final scrollBack = terminal.buffer.scrollBack;
  final topIndex = scrollBack.clamp(0, terminal.buffer.lines.length - 1);
  final bottomIndex = (scrollBack + terminal.viewHeight - 1).clamp(
    0,
    terminal.buffer.lines.length - 1,
  );
  final topLine = terminal.buffer.lines[topIndex].getText();
  final bottomLine = terminal.buffer.lines[bottomIndex].getText();
  return 'view=${terminal.viewWidth}x${terminal.viewHeight} '
      'lines=${terminal.buffer.lines.length} scrollBack=$scrollBack '
      'mouseMode=${terminal.mouseMode} top[$topIndex]="$topLine" '
      'bottom[$bottomIndex]="$bottomLine"';
}

class _IndexedProbe with IndexedItem {}

void main() {
  group('Terminal alt-buffer behavior', () {
    test('trimStart detaches trimmed indexed items', () {
      final buffer = IndexAwareCircularBuffer<_IndexedProbe>(4);
      final a = _IndexedProbe();
      final b = _IndexedProbe();
      final c = _IndexedProbe();

      buffer.push(a);
      buffer.push(b);
      buffer.push(c);

      expect(a.attached, isTrue);
      expect(b.attached, isTrue);
      expect(c.attached, isTrue);

      buffer.trimStart(1);

      expect(a.attached, isFalse);
      expect(b.attached, isTrue);
      expect(c.attached, isTrue);
    });

    test('push overflow keeps all addressable items attached', () {
      final buffer = IndexAwareCircularBuffer<_IndexedProbe>(3);
      final a = _IndexedProbe();
      final b = _IndexedProbe();
      final c = _IndexedProbe();
      final d = _IndexedProbe();

      buffer.push(a);
      buffer.push(b);
      buffer.push(c);
      buffer.push(d);

      expect(a.attached, isFalse);
      expect(buffer.length, 3);
      expect(buffer[0].attached, isTrue);
      expect(buffer[1].attached, isTrue);
      expect(buffer[2].attached, isTrue);
      expect(identical(buffer[0], b), isTrue);
      expect(identical(buffer[1], c), isTrue);
      expect(identical(buffer[2], d), isTrue);
    });

    test('push growth without overflow keeps earlier items attached', () {
      final buffer = IndexAwareCircularBuffer<_IndexedProbe>(200);
      final items = List<_IndexedProbe>.generate(35, (_) => _IndexedProbe());

      for (final item in items.take(24)) {
        buffer.push(item);
      }
      for (final item in items.skip(24)) {
        buffer.push(item);
      }

      expect(buffer.length, 35);
      for (var i = 0; i < buffer.length; i++) {
        expect(buffer[i].attached, isTrue, reason: 'item $i detached after push growth');
      }
      expect(identical(buffer[0], items[0]), isTrue);
      expect(identical(buffer[34], items[34]), isTrue);
    });

    test('empty alt buffer pre-resize state is stable', () {
      final terminal = Terminal(maxLines: 200);
      terminal.write('\x1b[?1049h');

      expect(terminal.buffer.lines.length, 24);
      expect(terminal.buffer.scrollBack, 0);
      expect(terminal.buffer.cursorY, 0);
      expect(terminal.buffer.absoluteCursorY, 0);
      expect(terminal.buffer.lines[0].isWrapped, isFalse);
      expect(terminal.buffer.lines[23].isWrapped, isFalse);
      expect(terminal.buffer.lines[0].attached, isTrue);
      expect(terminal.buffer.lines[23].attached, isTrue);
    });

    test('empty alt buffer height-only grow resize keeps all addressable lines attached', () {
      final terminal = Terminal(maxLines: 200);
      terminal.write('\x1b[?1049h');

      terminal.resize(80, 35);

      expect(terminal.buffer.lines.length, 35);
      for (var i = 0; i < terminal.buffer.lines.length; i++) {
        expect(
          terminal.buffer.lines[i].attached,
          isTrue,
          reason: 'line $i detached after empty height-only grow resize',
        );
      }
    });

    test('filled alt buffer without scroll keeps addressable lines attached', () {
      final terminal = Terminal(maxLines: 200);
      terminal.write('\x1b[?1049h');
      terminal.write('\x1b[2J\x1b[H');
      terminal.write(
        List<String>.generate(
          24,
          (index) => 'row $index',
        ).join('\r\n'),
      );

      expect(terminal.buffer.lines.length, 24);
      expect(terminal.buffer.scrollBack, 0);
      expect(terminal.buffer.lines[0].attached, isTrue);
      expect(terminal.buffer.lines[23].attached, isTrue);
    });

    test('filled alt buffer after first scroll shows detached active line', () {
      final terminal = Terminal(maxLines: 200);
      terminal.write('\x1b[?1049h');
      terminal.write('\x1b[2J\x1b[H');
      terminal.write(
        List<String>.generate(
          24,
          (index) => 'row $index',
        ).join('\r\n'),
      );
      terminal.write('\r\n(END)');
      terminal.write('\x1b[?1000h');
      terminal.write('\x1b[?1002h');

      expect(terminal.buffer.lines.length, 24);
      expect(terminal.buffer.scrollBack, 0);
      expect(terminal.buffer.cursorY, greaterThanOrEqualTo(0));
      expect(terminal.buffer.absoluteCursorY, greaterThanOrEqualTo(0));
      expect(terminal.buffer.lines[0].attached, isTrue);
      expect(terminal.buffer.lines[23].attached, isTrue);
    });

    test('alt buffer height-only grow resize keeps all addressable lines attached', () {
      final terminal = Terminal(maxLines: 200);
      terminal.write('\x1b[?1049h');
      terminal.write('\x1b[2J\x1b[H');
      terminal.write(
        List<String>.generate(
          24,
          (index) => '[2026-06-21 23:15:20,5${index.toString().padLeft(2, '0')}] [ INFO] row $index',
        ).join('\r\n'),
      );
      terminal.write('\r\n(END)');
      terminal.write('\x1b[?1000h');
      terminal.write('\x1b[?1002h');

      terminal.resize(80, 35);

      expect(terminal.buffer.lines.length, 35);
      for (var i = 0; i < terminal.buffer.lines.length; i++) {
        expect(
          terminal.buffer.lines[i].attached,
          isTrue,
          reason: 'line $i detached after height-only grow resize',
        );
      }
    });

    test('alt buffer grow resize keeps all addressable lines attached', () {
      final terminal = Terminal(maxLines: 200);
      terminal.write('\x1b[?1049h');
      terminal.write('\x1b[2J\x1b[H');
      terminal.write(
        List<String>.generate(
          24,
          (index) => '[2026-06-21 23:15:20,5${index.toString().padLeft(2, '0')}] [ INFO] row $index',
        ).join('\r\n'),
      );
      terminal.write('\r\n(END)');
      terminal.write('\x1b[?1000h');
      terminal.write('\x1b[?1002h');

      terminal.resize(57, 35);

      expect(terminal.buffer.lines.length, 35);
      for (var i = 0; i < terminal.buffer.lines.length; i++) {
        expect(
          terminal.buffer.lines[i].attached,
          isTrue,
          reason: 'line $i detached after grow resize',
        );
      }
    });

    test('alt buffer clearScrollback keeps all addressable lines attached', () {
      final terminal = Terminal(maxLines: 200);
      terminal.write('\x1b[?1049h');
      terminal.write('\x1b[2J\x1b[H');
      terminal.write(
        List<String>.generate(
          24,
          (index) => '[2026-06-21 23:15:20,5${index.toString().padLeft(2, '0')}] [ INFO] row $index',
        ).join('\r\n'),
      );
      terminal.write('\r\n(END)');
      terminal.write('\x1b[?1000h');
      terminal.write('\x1b[?1002h');

      terminal.resize(57, 35);
      terminal.buffer.clearScrollback();

      expect(terminal.buffer.lines.length, 35);
      for (var i = 0; i < terminal.buffer.lines.length; i++) {
        expect(
          terminal.buffer.lines[i].attached,
          isTrue,
          reason: 'line $i detached after clearScrollback',
        );
      }
    });
    test('alt buffer EOF-like state keeps visible rows in scrollback window', () {
      final terminal = Terminal(maxLines: 200);
      terminal.write('\x1b[?1049h');
      terminal.write('\x1b[2J\x1b[H');
      terminal.write(
        List<String>.generate(
          24,
          (index) => '[2026-06-21 23:15:20,5${index.toString().padLeft(2, '0')}] [ INFO] row $index',
        ).join('\r\n'),
      );
      terminal.write('\r\n(END)');

      expect(terminal.isUsingAltBuffer, isTrue);
      expect(terminal.buffer.lines.length, greaterThanOrEqualTo(terminal.viewHeight));
      expect(terminal.buffer.scrollBack, greaterThanOrEqualTo(0));

      final topVisibleLine = terminal.buffer.lines[terminal.buffer.scrollBack].getText();
      final bottomVisibleLine = terminal.buffer.lines[
        terminal.buffer.scrollBack + terminal.viewHeight - 1
      ].getText();

      expect(topVisibleLine, contains('row'));
      expect(bottomVisibleLine, anyOf(contains('row'), contains('(END)')));
    });
    testWidgets('direct controller selection works with EOF-like 24-row viewport plus END', (
      tester,
    ) async {
      final terminal = Terminal(maxLines: 200);
      final controller = TerminalController(
        pointerInputs: const PointerInputs.all(),
      );
      final scrollController = ScrollController();
      final focusNode = FocusNode();
      final viewKey = GlobalKey<TerminalViewState>();

      terminal.write('\x1b[?1049h');
      terminal.write('\x1b[2J\x1b[H');
      terminal.write(
        List<String>.generate(
          24,
          (index) => '[2026-06-21 23:15:20,5${index.toString().padLeft(2, '0')}] [ INFO] row $index',
        ).join('\r\n'),
      );
      terminal.write('\r\n(END)');
      terminal.write('\x1b[?1000h');
      terminal.write('\x1b[?1002h');

      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: SizedBox(
              width: 900,
              height: 520,
              child: TerminalView(
                terminal,
                key: viewKey,
                controller: controller,
                scrollController: scrollController,
                focusNode: focusNode,
                shortcuts: const <ShortcutActivator, Intent>{},
                textStyle: const TerminalStyle(fontSize: 14),
                simulateScroll: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        terminal.buffer.lines[1].attached,
        isTrue,
        reason: 'buffer line 1 detached while still addressable; ${_terminalDebugSnapshot(terminal)}',
      );

      final base = terminal.buffer.createAnchorFromOffset(const CellOffset(2, 1));
      final extent = terminal.buffer.createAnchorFromOffset(const CellOffset(12, 1));
      expect(
        base.attached,
        isTrue,
        reason: 'base anchor detached immediately; ${_terminalDebugSnapshot(terminal)}',
      );
      expect(
        extent.attached,
        isTrue,
        reason: 'extent anchor detached immediately; ${_terminalDebugSnapshot(terminal)}',
      );
      controller.setSelection(base, extent);
      final selection = controller.selection;

      expect(
        selection,
        isNotNull,
        reason: 'direct controller selection failed; ${_terminalDebugSnapshot(terminal)}',
      );
      expect(selection!.normalized.begin.y, lessThanOrEqualTo(2));
      expect(selection.normalized.end.y, greaterThanOrEqualTo(
        selection.normalized.begin.y,
      ));

      focusNode.dispose();
      scrollController.dispose();
    });
    testWidgets('selection still starts near top after EOF-like alt buffer state', (
      tester,
    ) async {
      final terminal = Terminal(maxLines: 200);
      final controller = TerminalController(
        pointerInputs: const PointerInputs.all(),
      );
      final scrollController = ScrollController();
      final focusNode = FocusNode();

      terminal.write('\x1b[?1049h');
      terminal.write('\x1b[2J\x1b[H');
      final eofViewport = <String>[
        '[2026-06-21 23:15:20,528] [ INFO] log row 18',
        '[2026-06-21 23:15:20,529] [ INFO] log row 19',
        '[2026-06-21 23:15:20,530] [ INFO] log row 20',
        '[2026-06-21 23:15:20,531] [ INFO] log row 21',
        '[2026-06-21 23:15:20,532] [ INFO] log row 22',
        '[2026-06-21 23:15:20,533] [ INFO] log row 23',
        '(END)',
      ].join('\r\n');
      terminal.write(eofViewport);
      terminal.write('\x1b[?1000h');
      terminal.write('\x1b[?1002h');

      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: SizedBox(
              width: 900,
              height: 520,
              child: TerminalView(
                terminal,
                controller: controller,
                scrollController: scrollController,
                focusNode: focusNode,
                shortcuts: const <ShortcutActivator, Intent>{},
                textStyle: const TerminalStyle(fontSize: 14),
                simulateScroll: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final terminalFinder = find.byType(TerminalView);
      final topLeft = tester.getTopLeft(terminalFinder);

      final gesture = await tester.startGesture(
        topLeft + const Offset(40, 24),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(topLeft + const Offset(220, 88));
      await tester.pump();

      final selection = controller.selection;
      expect(selection, isNotNull);
      expect(selection!.normalized.begin.y, lessThanOrEqualTo(2));
      expect(selection.normalized.end.y, greaterThanOrEqualTo(
        selection.normalized.begin.y,
      ));

      await gesture.up();
      await tester.pump();

      focusNode.dispose();
      scrollController.dispose();
    });
    testWidgets('drag selection still works in alt buffer with mouse mode enabled', (
      tester,
    ) async {
      final terminal = Terminal(maxLines: 200);
      final controller = TerminalController(
        pointerInputs: const PointerInputs.all(),
      );
      final scrollController = ScrollController();
      final focusNode = FocusNode();

      // Switch to alt buffer, fill visible rows, and enable mouse reporting
      // similar to how less/vim may behave after navigation commands.
      terminal.write('\x1b[?1049h');
      final visibleLines = List.generate(24, (index) => 'alt row $index').join('\r\n');
      terminal.write(visibleLines);
      terminal.write('\x1b[?1000h');
      terminal.write('\x1b[?1002h');

      expect(terminal.isUsingAltBuffer, isTrue);
      expect(terminal.mouseMode, isNot(MouseMode.none));

      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: SizedBox(
              width: 900,
              height: 520,
              child: TerminalView(
                terminal,
                controller: controller,
                scrollController: scrollController,
                focusNode: focusNode,
                shortcuts: const <ShortcutActivator, Intent>{},
                textStyle: const TerminalStyle(fontSize: 14),
                simulateScroll: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final terminalFinder = find.byType(TerminalView);
      expect(terminalFinder, findsOneWidget);

      final topLeft = tester.getTopLeft(terminalFinder);

      final gesture = await tester.startGesture(
        topLeft + const Offset(40, 30),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();

      await gesture.moveTo(topLeft + const Offset(260, 140));
      await tester.pump();

      expect(controller.selection, isNotNull);
      expect(controller.selection!.normalized.begin.y, greaterThanOrEqualTo(0));
      expect(controller.selection!.normalized.end.y, greaterThanOrEqualTo(
        controller.selection!.normalized.begin.y,
      ));
      expect(controller.suspendedPointerInputs, isTrue);

      await gesture.up();
      await tester.pump();

      expect(controller.selection, isNotNull);
      expect(controller.suspendedPointerInputs, isFalse);

      focusNode.dispose();
      scrollController.dispose();
    });

    testWidgets('selection can start from upper viewport area in alt buffer', (
      tester,
    ) async {
      final terminal = Terminal(maxLines: 200);
      final controller = TerminalController(
        pointerInputs: const PointerInputs.all(),
      );
      final scrollController = ScrollController();
      final focusNode = FocusNode();

      terminal.write('\x1b[?1049h');
      terminal.write(List.generate(24, (index) => 'viewport line $index').join('\r\n'));
      terminal.write('\x1b[?1002h');

      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: SizedBox(
              width: 900,
              height: 520,
              child: TerminalView(
                terminal,
                controller: controller,
                scrollController: scrollController,
                focusNode: focusNode,
                shortcuts: const <ShortcutActivator, Intent>{},
                textStyle: const TerminalStyle(fontSize: 14),
                simulateScroll: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final terminalFinder = find.byType(TerminalView);
      final topLeft = tester.getTopLeft(terminalFinder);

      final gesture = await tester.startGesture(
        topLeft + const Offset(36, 24),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      await gesture.moveTo(topLeft + const Offset(160, 48));
      await tester.pump();

      final selection = controller.selection;
      expect(selection, isNotNull);
      expect(selection!.normalized.begin.y, lessThanOrEqualTo(2));

      await gesture.up();
      await tester.pump();

      focusNode.dispose();
      scrollController.dispose();
    });
  });
}
