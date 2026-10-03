import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/core/theme/app_theme.dart';

class _Swatch extends StatelessWidget {
  const _Swatch();

  @override
  Widget build(BuildContext context) =>
      ColoredBox(key: const ValueKey('swatch'), color: AppColors.surface);
}

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int taps = 0;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => setState(() => taps++),
    child: Text('taps $taps', textDirection: TextDirection.ltr),
  );
}

Color swatch(WidgetTester tester) =>
    tester.widget<ColoredBox>(find.byKey(const ValueKey('swatch'))).color;

void main() {
  tearDown(() => AppColors.palette = AppPalette.dark);

  testWidgets('colors follow the OS and update when it changes', (
    tester,
  ) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);

    await tester.pumpWidget(
      FollowSystemBrightness(
        child: MaterialApp(
          theme: appLightTheme,
          darkTheme: appTheme,
          themeMode: ThemeMode.system,
          home: const Column(children: [_Swatch(), _Counter()]),
        ),
      ),
    );
    expect(swatch(tester), AppPalette.light.surface);
    expect(
      Theme.of(tester.element(find.byType(_Counter))).brightness,
      Brightness.light,
    );

    await tester.tap(find.text('taps 0'));
    await tester.pump();

    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(swatch(tester), AppPalette.dark.surface, reason: 'const rebuilt');
    expect(find.text('taps 1'), findsOneWidget, reason: 'state kept');
  });
}
