import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/connection_manager/connection_manager.dart';
import 'package:portix/src/connection_manager/mock_backend.dart';
import 'package:portix/src/connection_manager/rust_bridge_backend.dart';
import 'package:portix/src/connection_manager/session_models.dart';
import 'package:portix/src/connection_manager/ssh_profile.dart';
import 'package:portix/src/domain/entities/ssh/ssh_profile.dart' as domain;

class _RecordingBackend extends MockConnectionBackend {
  final connected = <SshProfile>[];
  final inputs = <String>[];

  @override
  Future<String> connect(SshProfile profile) {
    connected.add(profile);
    return super.connect(profile);
  }

  @override
  Future<void> sendTerminalInput(String sessionId, String data) async =>
      inputs.add(data);
}

final _profile = SshProfile.fromDomain(
  const domain.SshProfile(
    id: 'p1',
    name: 'cluster',
    host: 'example.test',
    port: 22,
    username: 'me',
    group: '',
    tags: [],
    authMethod: domain.AuthMethod.sshKey,
    credentialLabel: '',
    defaultPath: '~',
    status: domain.ConnectionStatus.offline,
    color: domain.ProfileColor.cyan,
    startupCommand: 'cd /srv',
  ),
);

void main() {
  test('the command reaches the Rust profile; a plain one has none', () {
    expect(toRustProfile(_profile).command, isNull);
    expect(
      toRustProfile(_profile.copyWith(command: 'kubectl exec -it x')).command,
      'kubectl exec -it x',
    );
  });

  test('a command session is not a terminal tab and types nothing', () async {
    final backend = _RecordingBackend();
    final manager = ConnectionManager(backend: backend);
    addTearDown(manager.dispose);
    final statuses = <ConnectionStatus>[];
    manager.commandStatusStream.listen((e) => statuses.add(e.status));

    final id = (await manager.openCommandSession(
      _profile,
      'kubectl exec -it pod -- sh',
    )).fold((_) => null, (id) => id);
    await Future<void>.delayed(const Duration(milliseconds: 600));

    expect(id, isNotNull);
    expect(backend.connected.single.command, 'kubectl exec -it pod -- sh');
    expect(manager.sessions, isEmpty, reason: 'no terminal tab');
    // Not typed into a shell, and the profile's startup command is skipped.
    expect(backend.inputs, isEmpty);
    expect(statuses, contains(ConnectionStatus.connected));
  });
}
