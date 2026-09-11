import 'dart:ui';

import 'package:flutter/material.dart';
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
        expect(
          buffer[i].attached,
          isTrue,
          reason: 'item $i detached after push growth',
        );
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

    test(
      'empty alt buffer height-only grow resize keeps all addressable lines attached',
      () {
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
      },
    );

    test(
      'filled alt buffer without scroll keeps addressable lines attached',
      () {
        final terminal = Terminal(maxLines: 200);
        terminal.write('\x1b[?1049h');
        terminal.write('\x1b[2J\x1b[H');
        terminal.write(
          List<String>.generate(24, (index) => 'row $index').join('\r\n'),
        );

        expect(terminal.buffer.lines.length, 24);
        expect(terminal.buffer.scrollBack, 0);
        expect(terminal.buffer.lines[0].attached, isTrue);
        expect(terminal.buffer.lines[23].attached, isTrue);
      },
    );

    test('filled alt buffer after first scroll shows detached active line', () {
      final terminal = Terminal(maxLines: 200);
      terminal.write('\x1b[?1049h');
      terminal.write('\x1b[2J\x1b[H');
      terminal.write(
        List<String>.generate(24, (index) => 'row $index').join('\r\n'),
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

    test(
      'alt buffer height-only grow resize keeps all addressable lines attached',
      () {
        final terminal = Terminal(maxLines: 200);
        terminal.write('\x1b[?1049h');
        terminal.write('\x1b[2J\x1b[H');
        terminal.write(
          List<String>.generate(
            24,
            (index) =>
                '[2026-06-21 23:15:20,5${index.toString().padLeft(2, '0')}] [ INFO] row $index',
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
      },
    );

    test('alt buffer grow resize keeps all addressable lines attached', () {
      final terminal = Terminal(maxLines: 200);
      terminal.write('\x1b[?1049h');
      terminal.write('\x1b[2J\x1b[H');
      terminal.write(
        List<String>.generate(
          24,
          (index) =>
              '[2026-06-21 23:15:20,5${index.toString().padLeft(2, '0')}] [ INFO] row $index',
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
          (index) =>
              '[2026-06-21 23:15:20,5${index.toString().padLeft(2, '0')}] [ INFO] row $index',
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
          (index) =>
              '[2026-06-21 23:15:20,5${index.toString().padLeft(2, '0')}] [ INFO] row $index',
        ).join('\r\n'),
      );
      terminal.write('\r\n(END)');

      expect(terminal.isUsingAltBuffer, isTrue);
      expect(
        terminal.buffer.lines.length,
        greaterThanOrEqualTo(terminal.viewHeight),
      );
      expect(terminal.buffer.scrollBack, greaterThanOrEqualTo(0));

      final topVisibleLine = terminal.buffer.lines[terminal.buffer.scrollBack]
          .getText();
      final bottomVisibleLine = terminal
          .buffer
          .lines[terminal.buffer.scrollBack + terminal.viewHeight - 1]
          .getText();

      expect(topVisibleLine, contains('row'));
      expect(bottomVisibleLine, anyOf(contains('row'), contains('(END)')));
    });
    testWidgets(
      'direct controller selection works with EOF-like 24-row viewport plus END',
      (tester) async {
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
            (index) =>
                '[2026-06-21 23:15:20,5${index.toString().padLeft(2, '0')}] [ INFO] row $index',
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
          reason:
              'buffer line 1 detached while still addressable; ${_terminalDebugSnapshot(terminal)}',
        );

        final base = terminal.buffer.createAnchorFromOffset(
          const CellOffset(2, 1),
        );
        final extent = terminal.buffer.createAnchorFromOffset(
          const CellOffset(12, 1),
        );
        expect(
          base.attached,
          isTrue,
          reason:
              'base anchor detached immediately; ${_terminalDebugSnapshot(terminal)}',
        );
        expect(
          extent.attached,
          isTrue,
          reason:
              'extent anchor detached immediately; ${_terminalDebugSnapshot(terminal)}',
        );
        controller.setSelection(base, extent);
        final selection = controller.selection;

        expect(
          selection,
          isNotNull,
          reason:
              'direct controller selection failed; ${_terminalDebugSnapshot(terminal)}',
        );
        expect(selection!.normalized.begin.y, lessThanOrEqualTo(2));
        expect(
          selection.normalized.end.y,
          greaterThanOrEqualTo(selection.normalized.begin.y),
        );

        focusNode.dispose();
        scrollController.dispose();
      },
    );
    testWidgets(
      'selection still starts near top after EOF-like alt buffer state',
      (tester) async {
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
        expect(
          selection.normalized.end.y,
          greaterThanOrEqualTo(selection.normalized.begin.y),
        );

        await gesture.up();
        await tester.pump();

        focusNode.dispose();
        scrollController.dispose();
      },
    );
    testWidgets(
      'drag selection still works in alt buffer with mouse mode enabled',
      (tester) async {
        final terminal = Terminal(maxLines: 200);
        final controller = TerminalController(
          pointerInputs: const PointerInputs.all(),
        );
        final scrollController = ScrollController();
        final focusNode = FocusNode();

        // Switch to alt buffer, fill visible rows, and enable mouse reporting
        // similar to how less/vim may behave after navigation commands.
        terminal.write('\x1b[?1049h');
        final visibleLines = List.generate(
          24,
          (index) => 'alt row $index',
        ).join('\r\n');
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
        expect(
          controller.selection!.normalized.begin.y,
          greaterThanOrEqualTo(0),
        );
        expect(
          controller.selection!.normalized.end.y,
          greaterThanOrEqualTo(controller.selection!.normalized.begin.y),
        );
        expect(controller.suspendedPointerInputs, isTrue);

        await gesture.up();
        await tester.pump();

        expect(controller.selection, isNotNull);
        expect(controller.suspendedPointerInputs, isFalse);

        focusNode.dispose();
        scrollController.dispose();
      },
    );

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
      terminal.write(
        List.generate(24, (index) => 'viewport line $index').join('\r\n'),
      );
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

  group('IndexAwareCircularBuffer', () {
    test('replaceWith keeps all slots addressable when the buffer has wrapped', () {
      // Regression for a crash where resize -> reflow -> replaceWith on a
      // buffer whose backing array had wrapped (startIndex != 0, e.g. after
      // scrollback overflow) left null slots in [0, length). The next resize's
      // reflow then read those slots via `lines[i]` and threw
      // "Null check operator used on a null value".
      const capacity = 4;
      final buffer = IndexAwareCircularBuffer<_IndexedProbe>(capacity);

      final original = List.generate(capacity + 3, (_) => _IndexedProbe());
      for (final item in original) {
        buffer.push(item);
      }
      // Buffer is now full (length == capacity) and wrapped: startIndex != 0.

      final replacement = List.generate(2, (_) => _IndexedProbe());
      buffer.replaceWith(replacement);

      expect(buffer.length, replacement.length);
      for (var i = 0; i < buffer.length; i++) {
        final line = buffer[i]; // operator [] -> used to throw here
        expect(line, replacement[i], reason: 'slot $i mismatch');
        expect(line.attached, isTrue, reason: 'slot $i detached');
        expect(line.index, i, reason: 'slot $i has wrong index');
      }
    });

    test('replaceWith drops leading overflow items on a wrapped buffer', () {
      // replacement.length > maxLength -> the leading (replacement.length -
      // maxLength) items are dropped, the survivors keep their relative order
      // at logical indices [0, maxLength).
      const capacity = 4;
      final buffer = IndexAwareCircularBuffer<_IndexedProbe>(capacity);
      for (var i = 0; i < capacity + 1; i++) {
        buffer.push(_IndexedProbe());
      }

      final replacement = List.generate(capacity + 3, (_) => _IndexedProbe());
      buffer.replaceWith(replacement);

      expect(buffer.length, capacity);
      // Survivors are the last `capacity` replacement items: replacement[3..6].
      expect(buffer[0], replacement[3]);
      expect(buffer[1], replacement[4]);
      expect(buffer[2], replacement[5]);
      expect(buffer[3], replacement[6]);
    });

    test('replaceWith with an empty replacement clears the buffer', () {
      final buffer = IndexAwareCircularBuffer<_IndexedProbe>(4);
      for (var i = 0; i < 6; i++) {
        buffer.push(_IndexedProbe());
      }
      buffer.replaceWith([]);
      expect(buffer.length, 0);
    });
  });

  group('main buffer reflow on resize', () {
    test(
      'width-change resizes after scrollback overflow keep all lines addressable',
      () {
        // Regression for the crash in the rendering library:
        // "Null check operator used on a null value" thrown from
        // IndexAwareCircularBuffer.[] via reflow during Terminal.resize.
        // The terminal overflows past maxLines (so the buffer wraps, i.e.
        // startIndex != 0), is then scrolled back to the viewport, and finally
        // resized with a width change twice. The buffer must keep every
        // addressable line valid across both reflows.
        final terminal = Terminal(maxLines: 50);
        // The buffers are created lazily on first access. Initialize them at the
        // default size first so a following shrink resize doesn't pop more lines
        // than currently exist in an uninitialized buffer.
        terminal.resize(80, 24);
        terminal.resize(80, 5);

        // Overflow past maxLines so the backing array wraps (startIndex != 0).
        for (var i = 0; i < 100; i++) {
          terminal.write('scrollback line $i\r\n');
        }
        expect(terminal.buffer.lines.length, 50);

        // Trim scrollback so length < maxLength while startIndex stays != 0,
        // which is the configuration that makes replaceWith leave nulls in
        // [0, length) on the buggy version.
        terminal.buffer.clearScrollback();
        expect(terminal.buffer.scrollBack, 0);
        expect(terminal.buffer.lines.length, lessThan(50));

        // Width-change resize #1: reflow reads the (still consistent) buffer,
        // then replaceWith rewrites it (corrupting it on the buggy version).
        terminal.resize(120, 5);
        // Width-change resize #2: reflow reads every line back via lines[i].
        // On the buggy version this throws "Null check operator ...".
        terminal.resize(80, 5);

        for (var i = 0; i < terminal.buffer.lines.length; i++) {
          final line = terminal.buffer.lines[i];
          expect(line, isNotNull, reason: 'line $i is null after resize');
          expect(line.attached, isTrue, reason: 'line $i detached after resize');
        }
      },
    );
  });
}
