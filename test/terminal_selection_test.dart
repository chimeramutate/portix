import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';

void main() {
  group('Terminal Selection Tests', () {
    test('Selection can be created and cleared', () {
      final terminal = Terminal();
      final controller = TerminalController();

      final anchor = terminal.buffer.createAnchorFromOffset(const CellOffset(5, 1));
      final extent = terminal.buffer.createAnchorFromOffset(const CellOffset(10, 2));

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
  });
}
