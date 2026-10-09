import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:portix/main.dart';
import 'package:portix/src/connection_manager/connection_backend.dart';
import 'package:portix/src/connection_manager/connection_manager.dart';
import 'package:portix/src/connection_manager/session_models.dart';
import 'package:portix/src/connection_manager/mock_backend.dart';
import 'package:portix/src/core/di/injection.dart';
import 'package:portix/src/domain/repositories/ssh/index.dart';
import 'package:portix/src/features/ssh_profiles/bloc/index.dart';
import 'support/refusing_host_key_backend.dart';

const _seedProfiles = [
  {
    'id': 'prod-api-01',
    'name': 'prod-api-01',
    'host': '10.0.0.11',
    'username': 'deploy',
    'group': 'Production',
    'tags': ['api'],
    'credentialLabel': '~/.ssh/id_ed25519',
    'defaultPath': '/srv/app',
  },
  {
    'id': 'prod-api-02',
    'name': 'prod-api-02',
    'host': '10.0.0.12',
    'username': 'deploy',
    'group': 'Production',
    'tags': ['api'],
    'credentialLabel': '~/.ssh/id_ed25519',
    'defaultPath': '/srv/app',
  },
];

/// Real DI, but with the mock SSH backend and a seeded temp profiles file so
/// tests never read or write the developer's ~/.portix/profiles.json.
Future<void> _configureTestDependencies({
  ConnectionBackend Function()? backend,
}) async {
  await GetIt.instance.reset();
  await configureDependencies();
  final dir = await Directory.systemTemp.createTemp('portix_test');
  final file = File('${dir.path}/profiles.json')
    ..writeAsStringSync(jsonEncode(_seedProfiles));
  sl
    ..unregister<ConnectionBackend>()
    ..registerLazySingleton<ConnectionBackend>(
      backend ?? MockConnectionBackend.new,
    )
    ..unregister<SshProfileRepository>()
    ..registerLazySingleton<SshProfileRepository>(
      () => SshProfileRepository(secretStore: sl(), storeFile: file),
    );
  addTearDown(() => dir.delete(recursive: true));
}

/// testWidgets that disposes DI before the binding's end-of-test check, so
/// ConnectionManager's heartbeat Timer.periodic is not reported as pending.
void _appTest(String description, WidgetTesterCallback body) {
  testWidgets(description, (tester) async {
    await body(tester);
    await GetIt.instance.reset();
  });
}

Future<void> _pumpPortixApp(
  WidgetTester tester,
  Size size, {
  ConnectionBackend Function()? backend,
}) async {
  await tester.binding.setSurfaceSize(size);
  // Native (FFI) library init is real async work that never completes inside
  // testWidgets' fake-async zone, so it must run in a real zone.
  await tester.runAsync(() => _configureTestDependencies(backend: backend));

  await tester.pumpWidget(const PortixApp());
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

/// The SFTP local pane lists the real filesystem (dart:io). Each awaited I/O
/// step only completes when real time passes outside the fake-async zone,
/// and its loading skeleton animates until then, so pumpAndSettle alone
/// never settles.
Future<void> _waitForLocalPane(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 50 && find.text('Loading').evaluate().isNotEmpty; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
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

  _appTest('renders the Portix SSH workspace', (tester) async {
    await _pumpPortixApp(tester, const Size(1600, 900));

    expect(find.text('Search profile, host, tag, or group'), findsOneWidget);
    expect(find.text('List SSH'), findsOneWidget);
    expect(find.text('prod-api-01'), findsWidgets);
    expect(find.text('Selected Profile'), findsNothing);

    await tester.tap(find.text('prod-api-01').first);
    await tester.pumpAndSettle();

    expect(find.text('Selected Profile'), findsOneWidget);
  });

  _appTest('renders the SFTP workspace from rail navigation', (
    tester,
  ) async {
    await _pumpPortixApp(tester, const Size(1600, 900));

    await tester.tap(find.text('SFTP'));
    await _waitForLocalPane(tester);
    await tester.pumpAndSettle();

    expect(find.text('SFTP Workspace'), findsWidgets);
    expect(find.text('Local'), findsOneWidget);
    expect(find.text('Remote'), findsOneWidget);
    expect(find.text('prod-api-01'), findsOneWidget);
    expect(find.text('Transfer Queue'), findsNothing);
  });

  _appTest('closing the only terminal session returns to SSH profiles', (
    tester,
  ) async {
    await _pumpPortixApp(tester, const Size(1600, 900));

    await tester.tap(find.text('Open SSH').first);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('close-tab-prod-api-01')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('close-tab-prod-api-01')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('close-tab-prod-api-01')), findsNothing);
    expect(find.text('List SSH'), findsOneWidget);
  });

  _appTest('terminal tools sit behind one button at the right', (
    tester,
  ) async {
    await _pumpPortixApp(tester, const Size(1600, 900));
    await tester.tap(find.text('Open SSH').first);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('terminal-theme')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('terminal-tools')));
    await tester.pumpAndSettle();
    for (final key in [
      'terminal-theme',
      'terminal-search',
      'save-session-state',
      'saved-sessions',
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget);
    }
  });

  _appTest('closing one of multiple terminal tabs activates the next tab', (
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
    expect(find.byTooltip('Close remote folder'), findsOneWidget);
  });

  _appTest('async host key refusal prompts, trusts, and reconnects', (
    tester,
  ) async {
    final backend = RefusingHostKeyBackend();
    await _pumpPortixApp(
      tester,
      const Size(1600, 900),
      backend: () => backend,
    );

    await tester.tap(find.text('Open SSH').first);
    await tester.pumpAndSettle();

    expect(find.text('Verify host key'), findsOneWidget);
    expect(find.textContaining('SHA256:abc'), findsOneWidget);
    await tester.tap(find.text('Trust and connect'));
    await tester.pumpAndSettle();

    expect(backend.trusted, ['SHA256:abc']);
    expect(find.text('Verify host key'), findsNothing);
    final sessions = sl<ConnectionManager>().sessions;
    expect(sessions.single.status, ConnectionStatus.connected);

    // The now-connected session is heartbeat-probed over real TCP; let that
    // probe's 4 s timeout run out before the test ends.
    await tester.pump(const Duration(seconds: 5));
  });

  _appTest(
    'compact list mode keeps overflow menu and primary actions visible',
    (tester) async {
      await _pumpPortixApp(tester, const Size(420, 900));
      await _openListView(tester);

      expect(find.text('Open SSH Session').first, findsOneWidget);
      expect(find.byIcon(Icons.more_vert_rounded), findsWidgets);

      await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
      await tester.pumpAndSettle();

      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Duplicate'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    },
  );

  _appTest('opening same profile from gallery reuses existing SSH tab', (
    tester,
  ) async {
    await _pumpPortixApp(tester, const Size(1600, 900));

    await tester.tap(find.text('Open SSH').first);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('close-tab-prod-api-01')), findsOneWidget);
    expect(find.byKey(const ValueKey('close-tab-prod-api-01 2')), findsNothing);

    await tester.tap(find.text('List SSH'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open SSH').first);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('close-tab-prod-api-01')), findsOneWidget);
    expect(find.byKey(const ValueKey('close-tab-prod-api-01 2')), findsNothing);
  });

  _appTest('new tab dialog supports end-to-end profile search', (
    tester,
  ) async {
    await _pumpPortixApp(tester, const Size(1600, 900));

    await tester.tap(find.text('Open SSH').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('new-terminal-tab')));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('connectable profiles available'),
      findsOneWidget,
    );

    await tester.enterText(find.byType(TextField).last, 'prod-api-02');
    await tester.pumpAndSettle();

    expect(find.textContaining('1 of'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('new-session-profile-prod-api-02')),
      findsOneWidget,
    );
  });

  test('saved profile is added and visible after filtered form flow', () async {
    await _configureTestDependencies();

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
              state.selectedProfile?.name == 'qa-api-01' &&
              state.searchQuery.isEmpty &&
              state.groupFilter == 'All profiles',
        ),
      ),
    );

    await bloc.close();
  });
}
