import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/features/ssh_profiles/bloc/index.dart';
import 'package:portix/src/features/ssh_profiles/widget/workspace_rail.dart';

void main() {
  Future<void> pump(WidgetTester tester, WorkspaceView view) =>
      tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Row(children: [WorkspaceRail(activeView: view)]),
          ),
        ),
      );

  testWidgets('icon-only rail names every view in a tooltip', (tester) async {
    await pump(tester, WorkspaceView.gallery);
    for (final label in ['SSH profiles', 'RDP', 'SFTP', 'Settings']) {
      expect(find.byTooltip(label), findsOneWidget);
      expect(find.text(label), findsNothing);
    }
    expect(
      tester.getSize(find.byType(WorkspaceRail)).width,
      workspaceRailWidth,
    );
  });

  testWidgets('only the active view is marked selected', (tester) async {
    await pump(tester, WorkspaceView.sftp);
    final handle = tester.ensureSemantics();
    expect(
      tester.getSemantics(find.byTooltip('SFTP')),
      isSemantics(isSelected: true),
    );
    expect(
      tester.getSemantics(find.byTooltip('RDP')),
      isSemantics(isSelected: false),
    );
    handle.dispose();
  });
}
