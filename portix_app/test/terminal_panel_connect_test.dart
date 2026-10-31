import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/connection_manager/connection_manager.dart';
import 'package:portix/src/connection_manager/mock_backend.dart';
import 'package:portix/src/core/di/injection.dart';
import 'package:portix/src/domain/entities/ssh/ssh_profile.dart';
import 'package:portix/src/domain/repositories/settings/settings_repository.dart';
import 'package:portix/src/domain/repositories/ssh/ssh_profile_repository.dart';
import 'package:portix/src/features/ssh_profiles/bloc/ssh_workspace_bloc.dart';
import 'package:portix/src/features/ssh_sessions/bloc/ssh_session_bloc.dart';
import 'package:portix/src/features/ssh_sessions/widget/remote/terminal_panel.dart';

class _MemorySettings extends SettingsRepository {
  @override
  Future<Map<String, String>> loadSettings() async => {};

  @override
  Future<void> saveSettings(Map<String, String> values) async {}
}

const _profile = SshProfile(
  id: 'p1',
  name: 'box',
  host: 'example.test',
  port: 22,
  username: 'me',
  group: '',
  tags: [],
  authMethod: AuthMethod.sshKey,
  credentialLabel: '',
  defaultPath: '~',
  status: ConnectionStatus.offline,
  color: ProfileColor.cyan,
);

void main() {
  late ConnectionManager manager;
  setUp(() {
    manager = ConnectionManager(backend: MockConnectionBackend());
    sl
      ..registerSingleton(manager)
      ..registerSingleton<SettingsRepository>(_MemorySettings());
  });
  tearDown(() => sl.reset());

  testWidgets('a new profile handed to a built panel connects after the '
      'frame, not during it', (tester) async {
    late StateSetter setProfile;
    SshProfile? profile;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MultiBlocProvider(
            providers: [
              BlocProvider(
                create: (_) =>
                    SshWorkspaceBloc(repository: SshProfileRepository()),
              ),
              BlocProvider(create: (_) => SshSessionBloc()),
            ],
            // Like the workspace page: something above the panel listens
            // to the manager and keeps its child.
            child: ListenableBuilder(
              listenable: manager,
              builder: (context, child) => child!,
              child: StatefulBuilder(
                builder: (context, setState) {
                  setProfile = setState;
                  return TerminalPanel(
                    profile: profile,
                    profiles: const [_profile],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    setProfile(() => profile = _profile);
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pump();
    expect(manager.sessions.map((s) => s.profileId), contains('p1'));
    await tester.pump(const Duration(seconds: 1)); // the mock's connect delay
  });
}
