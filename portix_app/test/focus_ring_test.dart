import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/core/widgets/index.dart';

void main() {
  testWidgets('a FocusRing card is reachable by Tab and activates on Enter', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FocusRing(
            child: Material(
              child: InkWell(onTap: () => taps++, child: const Text('Card')),
            ),
          ),
        ),
      ),
    );
    Border? ringBorder() {
      final box = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byType(FocusRing),
          matching: find.byType(DecoratedBox),
        ).first,
      );
      return (box.decoration as BoxDecoration).border as Border?;
    }

    expect(ringBorder(), isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(ringBorder()?.top.width, 2);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(taps, 1);
  });
}
