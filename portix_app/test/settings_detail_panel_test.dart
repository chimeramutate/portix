import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/features/settings/widget/settings_detail_panel.dart';
import 'package:portix/src/features/settings/widget/settings_models.dart';

void main() {
  testWidgets('section cards fit their rows at any text scale', (tester) async {
    const item = SettingsNavigationItem(
      id: 'general',
      title: 'General',
      icon: Icons.settings,
      headerTitle: 'General',
      headerSubtitle: '',
      profileTitle: 'Portix',
      profileSubtitle: '',
      sections: [
        SettingsDetailSection(
          title: 'Session Guardrails',
          rows: [
            SettingsDetailRow('A', '1'),
            SettingsDetailRow('B', '2'),
            SettingsDetailRow('C', '3'),
          ],
        ),
        SettingsDetailSection(
          title: 'Short',
          rows: [SettingsDetailRow('D', '4')],
        ),
      ],
    );
    await tester.binding.setSurfaceSize(const Size(900, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
        child: MaterialApp(
          home: Scaffold(
            body: SettingsDetailPanel(
              item: item,
              values: const {},
              defaults: const {},
              lastSavedAt: null,
              dirty: false,
              onChanged: (_, _) {},
              onRevert: null,
              onSave: null,
            ),
          ),
        ),
      ),
    );
    // A RenderFlex overflow is reported as a test exception.
    expect(tester.takeException(), isNull);
    expect(find.text('Session Guardrails'), findsOneWidget);
  });
}
