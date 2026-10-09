import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/features/ssh_profiles/bloc/index.dart';
import 'package:portix/src/features/ssh_profiles/widget/workspace_top_bar.dart';
import 'package:window_manager/window_manager.dart';

Future<void> _pump(
  WidgetTester tester,
  WorkspaceView view,
  TargetPlatform platform,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: WorkspaceTopBar(
          state: SshWorkspaceState(activeView: view),
          platform: platform,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('gallery bar is one 38px row with search and new profile', (
    tester,
  ) async {
    await _pump(tester, WorkspaceView.gallery, TargetPlatform.macOS);
    expect(
      tester.getSize(find.byType(WorkspaceTopBar)).height,
      workspaceTitleBarHeight,
    );
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byTooltip('New SSH Profile'), findsOneWidget);
  });

  testWidgets('macOS leaves window buttons to the native traffic lights', (
    tester,
  ) async {
    await _pump(tester, WorkspaceView.gallery, TargetPlatform.macOS);
    expect(find.byType(WindowCaptionButton), findsNothing);
    expect(find.byType(DragToMoveArea), findsOneWidget);
  });

  testWidgets('Linux and Windows draw minimize, maximize and close', (
    tester,
  ) async {
    for (final platform in [TargetPlatform.linux, TargetPlatform.windows]) {
      await _pump(tester, WorkspaceView.settings, platform);
      expect(find.byType(WindowCaptionButton), findsNWidgets(3));
      expect(find.text('Settings'), findsOneWidget);
    }
  });

  testWidgets('the terminal view keeps the bar so the window can be dragged', (
    tester,
  ) async {
    await _pump(tester, WorkspaceView.remoteFolder, TargetPlatform.linux);
    expect(find.text('Terminal'), findsOneWidget);
    expect(find.byType(DragToMoveArea), findsOneWidget);
  });
}
