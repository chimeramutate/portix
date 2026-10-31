import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/connection_manager/connection_manager.dart';
import 'package:portix/src/connection_manager/mock_backend.dart';
import 'package:portix/src/connection_manager/profile_credentials.dart';
import 'package:portix/src/connection_manager/profile_secret_store.dart';
import 'package:portix/src/core/di/injection.dart';
import 'package:portix/src/domain/entities/ssh/ssh_profile.dart';
import 'package:portix/src/domain/repositories/ssh/ssh_profile_repository.dart';
import 'package:portix/src/features/kubernetes/kubernetes_page.dart';
import 'package:portix/src/features/ssh_profiles/bloc/ssh_workspace_bloc.dart';

/// A keychain in memory.
class _MemorySecrets extends ProfileSecretStore {
  final passwords = <String, String>{};

  @override
  Future<void> savePassword(String profileId, String password) async =>
      passwords[profileId] = password;

  @override
  Future<String?> readPassword(String profileId) async =>
      passwords[profileId];
}

const _box = SshProfile(
  id: 'pw',
  name: 'box',
  host: 'example.test',
  port: 22,
  username: 'me',
  group: '',
  tags: [],
  authMethod: AuthMethod.password,
  credentialLabel: '',
  defaultPath: '~',
  status: ConnectionStatus.offline,
  color: ProfileColor.cyan,
  runsKubernetes: true,
);

void main() {
  late _MemorySecrets secrets;
  late Directory dir;
  setUp(() {
    secrets = _MemorySecrets();
    dir = Directory.systemTemp.createTempSync('kube_connect');
    sl.registerSingleton(
      ConnectionManager(
        backend: MockConnectionBackend(),
        credentials: ProfileCredentials(secretStore: secrets),
      ),
    );
  });
  tearDown(() async {
    kubeTabs.close(0);
    await sl.reset();
    dir.deleteSync(recursive: true);
  });

  testWidgets('an unsaved password is asked for, saved, then the checks '
      'run', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repository = SshProfileRepository(
      secretStore: secrets,
      storeFile: File('${dir.path}/profiles.json'),
    );
    late SshWorkspaceBloc bloc;
    await tester.runAsync(() async {
      await repository.saveProfile(_box);
      bloc = SshWorkspaceBloc(repository: repository)
        ..add(const ProfilesRequested());
      await bloc.stream.firstWhere((s) => s.profiles.isNotEmpty);
    });
    secrets.passwords.clear(); // as if the keychain never had it
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BlocProvider.value(value: bloc, child: const KubernetesPage()),
        ),
      ),
    );

    kubeTabs.current.pickServer('pw');
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(find.text('Password needed'), findsOneWidget);
    expect(find.text('Password for box'), findsOneWidget);
    expect(find.text('Could not open the cluster'), findsNothing);

    await tester.enterText(find.byType(TextField), 'secret');
    await tester.tap(find.text('Connect'));
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
    expect(secrets.passwords['pw'], 'secret');
    expect(find.text('Password for box'), findsNothing);
    // The mock backend cannot run commands, so the first step now fails;
    // a password profile can type it again.
    expect(find.text('Could not open the cluster'), findsOneWidget);
    await tester.tap(find.text('Enter password'));
    await tester.pump();
    expect(find.text('Password for box'), findsOneWidget);
    await tester.runAsync(bloc.close);
  });
}
