import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/connection_manager/connection_manager.dart';
import 'package:portix/src/connection_manager/mock_backend.dart';
import 'package:portix/src/core/di/injection.dart';
import 'package:portix/src/domain/entities/ssh/index.dart' as domain;
import 'package:portix/src/core/error/failure.dart';
import 'package:portix/src/core/usecase/either.dart';
import 'package:portix/src/domain/repositories/settings/settings_repository.dart';
import 'package:portix/src/domain/repositories/ssh/ssh_profile_repository.dart';
import 'package:portix/src/domain/usecases/ssh/index.dart';
import 'package:portix/src/features/ssh_profiles/bloc/ssh_workspace_bloc.dart';
import 'package:portix/src/features/ssh_sessions/bloc/index.dart';
import 'package:portix/src/features/ssh_sessions/widget/remote/index.dart';

class _TestSettingsRepository implements SettingsRepository {
  const _TestSettingsRepository();

  @override
  Future<void> clearSettings() async {}

  @override
  Future<Map<String, String>> loadSettings() async => const {};

  @override
  Future<void> saveSettings(Map<String, String> values) async {}
}

class _TestSshProfileRepository implements SshProfileRepository {
  const _TestSshProfileRepository(this.profiles);

  final List<domain.SshProfile> profiles;

  @override
  Future<Either<Failure, domain.SshProfile>> connect(domain.SshProfile profile) async {
    return Right(profile);
  }

  @override
  Future<Either<Failure, Unit>> deleteProfile(String id) async {
    return const Right(Unit());
  }

  @override
  Future<Either<Failure, List<domain.SshProfile>>> getProfiles() async {
    return Right(profiles);
  }

  @override
  Future<String?> readPasswordForEdit(String profileId) async => null;

  @override
  Future<Either<Failure, domain.SshProfile>> saveProfile(domain.SshProfile profile) async {
    return Right(profile);
  }

  @override
  Future<Either<Failure, domain.SshProfile>> testConnection(domain.SshProfile profile) async {
    return Right(profile);
  }
}

final _profiles = [
  const domain.SshProfile(
    id: 'profile-1',
    name: 'Mantap-68',
    host: '192.168.0.10',
    port: 22,
    username: 'root',
    group: 'Default',
    tags: ['prod'],
    authMethod: domain.AuthMethod.password,
    credentialLabel: 'Saved password',
    defaultPath: '/root',
    status: domain.ConnectionStatus.online,
    color: domain.ProfileColor.green,
  ),
  const domain.SshProfile(
    id: 'profile-2',
    name: 'Mantap-68 2',
    host: '192.168.0.11',
    port: 22,
    username: 'root',
    group: 'Default',
    tags: ['stage'],
    authMethod: domain.AuthMethod.password,
    credentialLabel: 'Saved password',
    defaultPath: '/root',
    status: domain.ConnectionStatus.online,
    color: domain.ProfileColor.cyan,
  ),
  const domain.SshProfile(
    id: 'profile-3',
    name: 'Mantap-69',
    host: '192.168.0.12',
    port: 22,
    username: 'root',
    group: 'Default',
    tags: ['dev'],
    authMethod: domain.AuthMethod.password,
    credentialLabel: 'Saved password',
    defaultPath: '/root',
    status: domain.ConnectionStatus.online,
    color: domain.ProfileColor.blue,
  ),
];

Future<void> _pumpTerminalPanel(
  WidgetTester tester, {
  double width = 1400,
  double height = 900,
}) async {
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => SshSessionBloc()),
        BlocProvider(
          create: (_) {
            final repository = _TestSshProfileRepository(_profiles);
            return SshWorkspaceBloc(
              getProfiles: GetProfiles(repository),
              saveProfile: SaveProfile(repository),
              testConnection: TestConnection(repository),
              deleteProfile: DeleteProfile(repository),
              readPasswordForEdit: ReadPasswordForEdit(repository),
            )..add(const NavigationChanged(WorkspaceView.remoteFolder));
          },
        ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: width,
            height: height,
            child: TerminalPanel(
              profile: _profiles.first,
              profiles: _profiles,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700));
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _openSessions(WidgetTester tester) async {
  for (final profile in _profiles.skip(1)) {
    await tester.tap(find.byKey(const ValueKey('new-terminal-tab')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byKey(ValueKey('new-session-profile-${profile.id}')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Finder _tabByLabel(String label) {
  final closeButton = find.byKey(ValueKey('close-tab-$label'));
  expect(closeButton, findsOneWidget);
  return find.ancestor(of: closeButton, matching: find.byType(GestureDetector)).first;
}

Future<void> _dragTabOntoTab(
  WidgetTester tester, {
  required String draggedLabel,
  required String targetLabel,
}) async {
  final draggedTab = _tabByLabel(draggedLabel);
  final targetTab = _tabByLabel(targetLabel);

  expect(draggedTab, findsOneWidget);
  expect(targetTab, findsOneWidget);

  final start = tester.getCenter(draggedTab);
  final end = tester.getCenter(targetTab);

  final gesture = await tester.startGesture(start, kind: PointerDeviceKind.mouse);
  await tester.pump();
  await gesture.moveTo(Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2));
  await tester.pump();
  await gesture.moveTo(end);
  await tester.pump();
  await gesture.up();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 150));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await sl.reset();
    sl
      ..registerSingleton<ConnectionManager>(
        ConnectionManager(backend: MockConnectionBackend()),
      )
      ..registerSingleton<SettingsRepository>(const _TestSettingsRepository());
  });

  tearDown(() async {
    await sl.reset();
  });

  testWidgets('dragging inactive tab onto active tab creates a workspace tab in TerminalPanel', (
    tester,
  ) async {
    await _pumpTerminalPanel(tester);
    await _openSessions(tester);

    expect(find.text('Mantap-68'), findsOneWidget);
    expect(find.text('Mantap-68 2'), findsOneWidget);
    expect(find.text('Mantap-69'), findsOneWidget);

    await _dragTabOntoTab(
      tester,
      draggedLabel: 'Mantap-69',
      targetLabel: 'Mantap-68',
    );

    expect(find.text('Workspace'), findsOneWidget);
    expect(find.text('Mantap-68 2'), findsOneWidget);
  });

  testWidgets('opening new-tab dialog stays stable and supports search', (
    tester,
  ) async {
    await _pumpTerminalPanel(tester);

    await tester.tap(find.byKey(const ValueKey('new-terminal-tab')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('New SSH session'), findsOneWidget);
    expect(find.text('3 connectable profiles available'), findsOneWidget);
    expect(find.byKey(const ValueKey('new-session-profile-profile-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('new-session-profile-profile-2')), findsOneWidget);
    expect(find.byKey(const ValueKey('new-session-profile-profile-3')), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, '69');
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('1 of 3 profiles match your search'), findsOneWidget);
    expect(find.byKey(const ValueKey('new-session-profile-profile-1')), findsNothing);
    expect(find.byKey(const ValueKey('new-session-profile-profile-2')), findsNothing);
    expect(find.byKey(const ValueKey('new-session-profile-profile-3')), findsOneWidget);
  });

  testWidgets('tab overflow controls appear when sessions exceed available width', (
    tester,
  ) async {
    await _pumpTerminalPanel(tester, width: 640, height: 900);
    await _openSessions(tester);
    await tester.pumpAndSettle();

    expect(find.byTooltip('Scroll tabs right'), findsOneWidget);

    await tester.tap(find.byTooltip('Scroll tabs right'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
