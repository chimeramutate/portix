import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/features/ssh_sessions/widget/remote/terminal_theme_picker.dart';
import 'package:portix/src/features/ssh_sessions/widget/remote/terminal_themes.dart';

void main() {
  testWidgets('a click applies the theme without closing the picker', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1400, 1000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final picked = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TerminalThemePicker(current: 'Portix', onSelected: picked.add),
        ),
      ),
    );

    final grid = tester.widget<GridView>(find.byType(GridView));
    final delegate = grid.childrenDelegate as SliverChildListDelegate;
    expect(delegate.children.map((card) => card.key), [
      for (final name in terminalThemeNames) ValueKey('terminal-theme-$name'),
    ]);
    expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('terminal-theme-Argonaut')));
    await tester.pump();

    expect(picked, ['Argonaut']);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('terminal-theme-Argonaut')),
        matching: find.byIcon(Icons.check_circle_rounded),
      ),
      findsOneWidget,
    );
    expect(find.byType(TerminalThemePicker), findsOneWidget);
  });

  test('every listed theme has its own palette', () {
    final backgrounds = {
      for (final name in terminalThemeNames)
        terminalThemeByName(name).background,
    };
    // Adwaita Dark and others must not fall back to the Portix default.
    expect(
      terminalThemeNames
          .where((n) => n != 'Portix')
          .every((n) => terminalThemeByName(n) != portixBuiltinTheme),
      isTrue,
    );
    expect(backgrounds.length, greaterThan(10));
  });
}
