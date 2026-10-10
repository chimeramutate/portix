import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/core/theme/app_theme.dart';
import 'package:portix/src/features/ssh_sessions/widget/remote/terminal_status_footer.dart';
import 'package:portix/src/features/ssh_sessions/widget/remote/terminal_workspace_view.dart';

double _closeOpacity(WidgetTester tester, String label) => tester
    .widget<Opacity>(
      find
          .ancestor(
            of: find.byKey(ValueKey('close-tab-$label')),
            matching: find.byType(Opacity),
          )
          .first,
    )
    .opacity;

void main() {
  test('usage stays neutral until 85%, amber until 95%, then danger', () {
    expect(usageLevelColor(.84), AppColors.text);
    expect(usageLevelColor(.85), AppColors.amber);
    expect(usageLevelColor(.94), AppColors.amber);
    expect(usageLevelColor(.95), AppColors.danger);
  });

  testWidgets('close shows on the active tab and on hover, not otherwise', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              TerminalSessionTab(
                sessionId: 'a',
                label: 'web',
                active: true,
                draggable: false,
                onClose: () {},
              ),
              TerminalSessionTab(
                sessionId: 'b',
                label: 'db',
                draggable: false,
                onClose: () {},
              ),
            ],
          ),
        ),
      ),
    );
    expect(_closeOpacity(tester, 'web'), 1);
    expect(_closeOpacity(tester, 'db'), 0);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(
      tester.getCenter(find.byKey(const ValueKey('terminal-session-tab-b'))),
    );
    await tester.pump();
    expect(_closeOpacity(tester, 'db'), 1);
    await mouse.removePointer();
  });
}
