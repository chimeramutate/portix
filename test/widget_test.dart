import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:portix/main.dart';
import 'package:portix/src/core/di/injection.dart';
import 'package:portix/src/features/ssh_profiles/bloc/index.dart';

Future<void> _pumpPortixApp(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  await GetIt.instance.reset();
  await configureDependencies();

  await tester.pumpWidget(const PortixApp());
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

Future<void> _openListView(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Change profile view'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('List').last);
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() async {
    await GetIt.instance.reset();
  });

  testWidgets('renders the Portix SSH workspace', (tester) async {
    await _pumpPortixApp(tester, const Size(1600, 900));

    expect(find.text('Portix'), findsOneWidget);
    expect(find.text('SSH Profiles'), findsOneWidget);
    expect(find.text('prod-api-01'), findsWidgets);
    expect(find.text('Selected Profile'), findsNothing);

    await tester.tap(find.text('prod-api-01').first);
    await tester.pumpAndSettle();

    expect(find.text('Selected Profile'), findsOneWidget);
  });

  testWidgets('renders the SFTP workspace from rail navigation', (
    tester,
  ) async {
    await _pumpPortixApp(tester, const Size(1600, 900));

    await tester.tap(find.text('SFTP'));
    await tester.pumpAndSettle();

    expect(find.text('SFTP Workspace'), findsWidgets);
    expect(find.text('Local'), findsOneWidget);
    expect(find.text('Remote / production'), findsOneWidget);
    expect(find.text('Transfer Queue'), findsNothing);
  });

  testWidgets('closing the only terminal session returns to SSH profiles', (
    tester,
  ) async {
    await _pumpPortixApp(tester, const Size(1600, 900));

    await tester.tap(find.text('Open SSH').first);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('close-tab-prod-api-01')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('close-tab-prod-api-01')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('close-tab-prod-api-01')), findsNothing);
    expect(find.text('SSH Profiles'), findsOneWidget);
  });

  testWidgets('closing one of multiple terminal tabs activates the next tab', (
    tester,
  ) async {
    await _pumpPortixApp(tester, const Size(1600, 900));

    await tester.tap(find.text('Open SSH').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('new-terminal-tab')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('new-session-profile-prod-api-01')),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('close-tab-prod-api-01')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('close-tab-prod-api-01 2')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('close-tab-prod-api-01 2')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('close-tab-prod-api-01')), findsOneWidget);
    expect(find.byKey(const ValueKey('close-tab-prod-api-01 2')), findsNothing);
    expect(find.text('Remote Folder'), findsOneWidget);
  });

  testWidgets('compact list mode keeps overflow menu and primary actions visible', (
    tester,
  ) async {
    await _pumpPortixApp(tester, const Size(420, 900));
    await _openListView(tester);

    expect(find.text('Open SSH Session').first, findsOneWidget);
    expect(find.text('Open SFTP').first, findsOneWidget);
    expect(find.byIcon(Icons.more_vert_rounded), findsWidgets);

    await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
    await tester.pumpAndSettle();

    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Duplicate'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('opening same profile from gallery reuses existing SSH tab', (
    tester,
  ) async {
    await _pumpPortixApp(tester, const Size(1600, 900));

    await tester.tap(find.text('Open SSH').first);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('close-tab-prod-api-01')), findsOneWidget);
    expect(find.byKey(const ValueKey('close-tab-prod-api-01 2')), findsNothing);

    await tester.tap(find.text('SSH Profiles'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open SSH').first);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('close-tab-prod-api-01')), findsOneWidget);
    expect(find.byKey(const ValueKey('close-tab-prod-api-01 2')), findsNothing);
  });

  testWidgets('new tab dialog supports end-to-end profile search', (tester) async {
    await _pumpPortixApp(tester, const Size(1600, 900));

    await tester.tap(find.text('Open SSH').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('new-terminal-tab')));
    await tester.pumpAndSettle();

    expect(find.textContaining('connectable profiles available'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, 'prod-api-02');
    await tester.pumpAndSettle();

    expect(find.textContaining('1 of'), findsOneWidget);
    expect(find.byKey(const ValueKey('new-session-profile-prod-api-02')), findsOneWidget);
  });

  test('saved profile is added and visible after filtered form flow', () async {
    await GetIt.instance.reset();
    await configureDependencies();

    final bloc = sl<SshWorkspaceBloc>()..add(const ProfilesRequested());
    await expectLater(
      bloc.stream,
      emitsThrough(
        predicate<SshWorkspaceState>(
          (state) => state.status == WorkspaceStatus.ready,
        ),
      ),
    );

    bloc
      ..add(const GroupFilterChanged('Staging'))
      ..add(const SearchChanged('hidden-filter'))
      ..add(const NewProfileRequested());
    await pumpEventQueue();

    bloc.add(
      const ProfileFormChanged(
        name: 'qa-api-01',
        host: '10.10.10.10',
        port: '22',
        username: 'deploy',
        group: 'Production',
        tags: 'qa, api',
        credentialLabel: 'id_qa_ed25519',
        defaultPath: '/srv/qa',
        startupCommand: '',
        terminalFontSize: '14',
      ),
    );
    bloc.add(const ProfileSaved());

    await expectLater(
      bloc.stream,
      emitsThrough(
        predicate<SshWorkspaceState>(
          (state) =>
              state.activeView == WorkspaceView.gallery &&
              state.profiles.any((profile) => profile.name == 'qa-api-01') &&
              state.filteredProfiles.any(
                (profile) => profile.name == 'qa-api-01',
              ) &&
              state.selectedProfile == null &&
              state.searchQuery.isEmpty &&
              state.groupFilter == 'All profiles',
        ),
      ),
    );

    await bloc.close();
  });
}
