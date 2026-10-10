import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/connection_manager/connection_manager.dart';
import 'package:portix/src/connection_manager/mock_backend.dart';
import 'package:portix/src/connection_manager/ssh_profile.dart';
import 'package:portix/src/domain/entities/ssh/index.dart' as domain;

class _InputRecordingBackend extends MockConnectionBackend {
  final inputs = <String>[];

  @override
  Future<void> sendTerminalInput(String sessionId, String data) async =>
      inputs.add(data);
}

domain.SshProfile _domainProfile(String startup) => domain.SshProfile(
  id: 'p1',
  name: 'web',
  host: 'example.test',
  port: 22,
  username: 'me',
  group: '',
  tags: const [],
  authMethod: domain.AuthMethod.sshKey,
  credentialLabel: '',
  defaultPath: '~',
  status: domain.ConnectionStatus.offline,
  color: domain.ProfileColor.cyan,
  startupCommand: startup,
);

void main() {
  test('the profile startup command is typed once after connecting', () async {
    final backend = _InputRecordingBackend();
    final manager = ConnectionManager(backend: backend);
    addTearDown(manager.dispose);

    await manager.connect(
      SshProfile.fromDomain(_domainProfile('  cd /srv/app && ls  ')),
    );
    await Future<void>.delayed(Duration.zero);

    expect(backend.inputs, ['cd /srv/app && ls\r']);
  });

  test('a blank startup command sends nothing', () async {
    final backend = _InputRecordingBackend();
    final manager = ConnectionManager(backend: backend);
    addTearDown(manager.dispose);

    await manager.connect(SshProfile.fromDomain(_domainProfile('   ')));
    await Future<void>.delayed(Duration.zero);

    expect(backend.inputs, isEmpty);
  });

  test('copyWith keeps the startup command', () {
    final profile = SshProfile.fromDomain(_domainProfile('htop'));
    expect(profile.copyWith(password: 'x').startupCommand, 'htop');
  });
}
