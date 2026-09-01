import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

// terminal testing is a bit tricky because it relies on mouse events and timers, so we have to use the flutter_test package to simulate user interactions and verify the behavior of the terminal selection feature.
void main() {
  group('Terminal Selection Tests', () {
    test('Selection can be created and cleared', () {
      final terminal = Terminal();
      final controller = TerminalController();

      final anchor = terminal.buffer.createAnchorFromOffset(
        const CellOffset(5, 1),
      );
      final extent = terminal.buffer.createAnchorFromOffset(
        const CellOffset(10, 2),
      );

      controller.setSelection(anchor, extent);

      expect(controller.selection, isNotNull);
      expect(controller.selection!.normalized.begin.x, equals(5));
      expect(controller.selection!.normalized.end.x, equals(10));

      controller.clearSelection();
      expect(controller.selection, isNull);
    });

    test('toggle selection mode works', () {
      final controller = TerminalController();

      expect(controller.selectionMode, equals(SelectionMode.line));

      controller.setSelectionMode(SelectionMode.block);
      expect(controller.selectionMode, equals(SelectionMode.block));

      controller.setSelectionMode(SelectionMode.line);
      expect(controller.selectionMode, equals(SelectionMode.line));
    });

    test('pointer input is suspended while there is an active selection', () {
      final terminal = Terminal();
      final controller = TerminalController(
        pointerInputs: const PointerInputs.all(),
      );

      expect(controller.shouldSendPointerInput(PointerInput.tap), isTrue);
      expect(controller.shouldSendPointerInput(PointerInput.drag), isTrue);

      controller.setSelection(
        terminal.buffer.createAnchorFromOffset(const CellOffset(0, 0)),
        terminal.buffer.createAnchorFromOffset(const CellOffset(4, 0)),
      );

      expect(controller.selection, isNotNull);
      expect(controller.shouldSendPointerInput(PointerInput.tap), isFalse);
      expect(controller.shouldSendPointerInput(PointerInput.drag), isFalse);

      controller.clearSelection();

      expect(controller.selection, isNull);
      expect(controller.shouldSendPointerInput(PointerInput.tap), isTrue);
      expect(controller.shouldSendPointerInput(PointerInput.drag), isTrue);
    });

    testWidgets('mouse drag creates selection in TerminalView', (tester) async {
      final terminal = Terminal(maxLines: 200);
      final controller = TerminalController(
        pointerInputs: const PointerInputs.all(),
      );
      final scrollController = ScrollController();
      final focusNode = FocusNode();

      final lines = List.generate(40, (index) => 'line $index').join('\r\n');
      terminal.write(lines);

      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: SizedBox(
              width: 800,
              height: 500,
              child: TerminalView(
                terminal,
                controller: controller,
                scrollController: scrollController,
                focusNode: focusNode,
                shortcuts: const <ShortcutActivator, Intent>{},
                textStyle: const TerminalStyle(fontSize: 14),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final terminalFinder = find.byType(TerminalView);
      expect(terminalFinder, findsOneWidget);

      final gesture = await tester.startGesture(
        tester.getTopLeft(terminalFinder) + const Offset(40, 40),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();

      await gesture.moveTo(
        tester.getTopLeft(terminalFinder) + const Offset(220, 120),
      );
      await tester.pump();

      expect(controller.selection, isNotNull);
      expect(controller.suspendedPointerInputs, isTrue);

      await gesture.up();
      await tester.pump();

      expect(controller.selection, isNotNull);
      expect(controller.suspendedPointerInputs, isFalse);

      focusNode.dispose();
      scrollController.dispose();
    });

    // Regression coverage for auto-scrolling the viewport while a block/character
    // selection is being dragged past the top/bottom edge of the visible
    // viewport.  See getSelectionDragScrollDelta() / _onSelectionAutoScrollTick().
    testWidgets(
      'dragging past the viewport edge auto-scrolls to reveal more of the buffer',
      (tester) async {
        final terminal = Terminal(maxLines: 200);
        final controller = TerminalController(
          pointerInputs: const PointerInputs.all(),
        );
        final scrollController = ScrollController();
        final focusNode = FocusNode();

        // More lines than fit in the viewport so there is scrollback to scroll into.
        terminal.write(List.generate(80, (i) => 'line $i\r\n').join());

        await tester.pumpWidget(
          MaterialApp(
            home: Material(
              child: SizedBox(
                width: 800,
                height: 400,
                child: TerminalView(
                  terminal,
                  controller: controller,
                  scrollController: scrollController,
                  focusNode: focusNode,
                  shortcuts: const <ShortcutActivator, Intent>{},
                  textStyle: const TerminalStyle(fontSize: 14),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final terminalFinder = find.byType(TerminalView);
        expect(terminalFinder, findsOneWidget);

        // Pin the viewport to the top so there is room to scroll downwards.
        expect(scrollController.position.maxScrollExtent, greaterThan(0.0));
        scrollController.jumpTo(0);
        await tester.pumpAndSettle();
        expect(scrollController.position.pixels, lessThanOrEqualTo(0.0));

        // Start a mouse selection drag in the middle of the viewport.
        final start =
            tester.getTopLeft(terminalFinder) + const Offset(100, 200);
        final gesture = await tester.startGesture(
          start,
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();

        // Drag the pointer past the BOTTOM edge of the viewport.  The viewport
        // should keep scrolling to reveal the scrollback below.
        final pastBottom =
            tester.getTopLeft(terminalFinder) + const Offset(100, 1200);
        await gesture.moveTo(pastBottom);
        // Let the periodic auto-scroll timer tick a few times.
        await tester.pump(const Duration(milliseconds: 120));

        // A non-collapsed selection was created (proving the mouse drag started,
        // which is also when the auto-scroll timer kicks in) and the viewport
        // followed the drag by scrolling downwards.
        expect(controller.suspendedPointerInputs, isTrue);
        expect(controller.selection, isNotNull);
        expect(scrollController.position.pixels, greaterThan(0.0));

        await gesture.up();
        await tester.pump();

        focusNode.dispose();
        scrollController.dispose();
      },
    );

    testWidgets(
      'dragging within the viewport does not auto-scroll the terminal',
      (tester) async {
        final terminal = Terminal(maxLines: 200);
        final controller = TerminalController(
          pointerInputs: const PointerInputs.all(),
        );
        final scrollController = ScrollController();
        final focusNode = FocusNode();

        terminal.write(List.generate(80, (i) => 'line $i\r\n').join());

        await tester.pumpWidget(
          MaterialApp(
            home: Material(
              child: SizedBox(
                width: 800,
                height: 400,
                child: TerminalView(
                  terminal,
                  controller: controller,
                  scrollController: scrollController,
                  focusNode: focusNode,
                  shortcuts: const <ShortcutActivator, Intent>{},
                  textStyle: const TerminalStyle(fontSize: 14),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final terminalFinder = find.byType(TerminalView);
        scrollController.jumpTo(0);
        await tester.pumpAndSettle();
        expect(scrollController.position.pixels, lessThanOrEqualTo(0.0));

        final start =
            tester.getTopLeft(terminalFinder) + const Offset(100, 200);
        final gesture = await tester.startGesture(
          start,
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();

        // Drag to another point still inside the 400px-tall viewport.
        final inside =
            tester.getTopLeft(terminalFinder) + const Offset(100, 380);
        await gesture.moveTo(inside);
        await tester.pump(const Duration(milliseconds: 120));

        // No auto-scroll should have happened because the pointer never left the
        // visible viewport.
        expect(scrollController.position.pixels, lessThanOrEqualTo(0.0));
        expect(controller.selection, isNotNull);

        await gesture.up();
        await tester.pump();

        focusNode.dispose();
        scrollController.dispose();
      },
    );
  });
}
