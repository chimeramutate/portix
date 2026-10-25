import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/core/widgets/side_panel.dart';
import 'package:portix/src/features/ssh_profiles/bloc/ssh_workspace_bloc.dart';
import 'package:portix/src/features/ssh_profiles/widget/workspace_shell.dart';

void main() {
  Future<void> pump(WidgetTester tester, Size size) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(
        home: WorkspaceShell(
          state: SshWorkspaceState(activeView: WorkspaceView.rdp),
          panel: SidePanel(title: 'Profiles', child: Text('panel body')),
          child: Text('content'),
        ),
      ),
    );
  }

  testWidgets('clicking the active rail item toggles the side panel', (
    tester,
  ) async {
    await pump(tester, const Size(1200, 800));
    expect(find.text('PROFILES'), findsOneWidget);
    expect(tester.getSize(find.byType(SidePanel)).width, sidePanelWidth);

    await tester.tap(find.byTooltip('RDP'));
    await tester.pump();
    expect(find.byType(SidePanel), findsNothing);
    expect(find.text('content'), findsOneWidget);

    await tester.tap(find.byTooltip('RDP'));
    await tester.pump();
    expect(find.text('panel body'), findsOneWidget);
  });

  testWidgets('narrow windows hide the side panel', (tester) async {
    await pump(tester, const Size(700, 800));
    expect(find.byType(SidePanel), findsNothing);
    expect(find.text('content'), findsOneWidget);
  });
}
