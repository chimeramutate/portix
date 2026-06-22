import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/features/ssh_sessions/controller/terminal_session_ui_controller.dart';
import 'package:xterm/xterm.dart';

void main() {
  group('TerminalSessionUiController', () {
    testWidgets(
      'session controller remains usable until disposal is explicitly run',
      (tester) async {
        final ui = TerminalSessionUiController(
          onInput: (_, __) {},
          onResize: (_, __, ___) {},
        );
        const sessionId = 'session-1';
        final controller = ui.controllerForSession(sessionId);
        final terminal = ui.terminalForSession(sessionId);
        final scrollController = ui.scrollControllerForSession(sessionId);
        final focusNode = ui.focusNodeForSession(sessionId);
        final viewKey = ui.viewKeyForSession(sessionId);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 640,
                height: 320,
                child: TerminalView(
                  terminal,
                  key: viewKey,
                  controller: controller,
                  scrollController: scrollController,
                  focusNode: focusNode,
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        controller.setSelection(
          terminal.buffer.createAnchor(0, 0),
          terminal.buffer.createAnchor(1, 0),
        );
        expect(controller.selection, isNotNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();

        expect(
          () => controller.clearSelection(),
          returnsNormally,
          reason: 'controller should still be valid before deferred disposal',
        );

        ui.disposeSession(sessionId);

        expect(
          () => controller.clearSelection(),
          throwsA(isA<FlutterError>()),
          reason: 'controller must reject use after session disposal',
        );

        ui.dispose();
      },
    );

    testWidgets(
      'session disposal is safe after terminal widget is removed from tree',
      (tester) async {
        final ui = TerminalSessionUiController(
          onInput: (_, __) {},
          onResize: (_, __, ___) {},
        );
        const sessionId = 'session-2';
        final controller = ui.controllerForSession(sessionId);
        final terminal = ui.terminalForSession(sessionId);
        final scrollController = ui.scrollControllerForSession(sessionId);
        final focusNode = ui.focusNodeForSession(sessionId);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TerminalView(
                terminal,
                controller: controller,
                scrollController: scrollController,
                focusNode: focusNode,
              ),
            ),
          ),
        );
        await tester.pump();

        await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
        await tester.pump();

        expect(
          () => ui.disposeSession(sessionId),
          returnsNormally,
          reason: 'deferred cleanup should work once the widget tree released the controller',
        );
        expect(
          ui.dispose,
          returnsNormally,
          reason: 'controller.dispose should not double-dispose removed session resources',
        );
      },
    );
  });
}
