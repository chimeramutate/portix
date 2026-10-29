import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/features/app_menu/app_menu.dart';

List<PlatformMenuItem> _flatten(List<PlatformMenuItem> items) => [
  for (final item in items) ...[
    item,
    if (item is PlatformMenu) ..._flatten(item.menus),
    if (item is PlatformMenuItemGroup) ..._flatten(item.members),
  ],
];

void main() {
  testWidgets(
    'the Portix menu offers Check for Updates, which asks Sparkle',
    (tester) async {
      final calls = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('portix/updater'),
        (call) async {
          calls.add(call.method);
          return null;
        },
      );
      await tester.pumpWidget(
        const MaterialApp(home: AppMenus(child: SizedBox())),
      );
      final bar = tester.widget<PlatformMenuBar>(find.byType(PlatformMenuBar));
      final portix = bar.menus.first as PlatformMenu;
      expect(portix.label, 'Portix');
      final item = _flatten(
        portix.menus,
      ).firstWhere((i) => i.label == 'Check for Updates…');
      item.onSelected!();
      await tester.pump();
      expect(calls, ['checkForUpdates']);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );
}
