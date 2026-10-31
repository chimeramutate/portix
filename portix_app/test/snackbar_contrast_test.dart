import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/core/theme/app_theme.dart';

double _contrast(Color a, Color b) {
  final hi = a.computeLuminance();
  final lo = b.computeLuminance();
  return ((hi > lo ? hi : lo) + .05) / ((hi > lo ? lo : hi) + .05);
}

void main() {
  for (final palette in [AppPalette.dark, AppPalette.light]) {
    // The fills call sites pass; null is a SnackBar left to the theme.
    final fills = <Color?>[
      null,
      palette.surfaceCard,
      palette.dangerTint,
      palette.greenTint,
    ];
    for (final fill in fills) {
      testWidgets('${palette.brightness.name} snackbar text reads on $fill', (
        tester,
      ) async {
        late ScaffoldMessengerState messenger;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(palette),
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  messenger = ScaffoldMessenger.of(context);
                  return const SizedBox.expand();
                },
              ),
            ),
          ),
        );
        messenger.showSnackBar(
          SnackBar(content: const Text('Failed'), backgroundColor: fill),
        );
        await tester.pumpAndSettle();

        final material = tester.widget<Material>(
          find
              .descendant(
                of: find.byType(SnackBar),
                matching: find.byType(Material),
              )
              .first,
        );
        final text = DefaultTextStyle.of(
          tester.element(find.text('Failed')),
        ).style.color!;
        expect(
          _contrast(text, material.color!),
          greaterThanOrEqualTo(4.5),
          reason: 'text $text on ${material.color}',
        );
      });
    }
  }
}
