import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/connection_manager/profile_credentials.dart';
import 'package:portix/src/domain/entities/ssh/index.dart' as domain;
import 'package:portix/src/features/sftp/controller/sftp_workspace_controller.dart';
import 'package:portix/src/sftp_client/sftp_manager.dart';

import 'support/fake_sftp_backend.dart';

const _profile = domain.SshProfile(
  id: 'p',
  name: 'p',
  host: '10.0.0.11',
  port: 22,
  username: 'deploy',
  group: 'Production',
  tags: [],
  authMethod: domain.AuthMethod.sshKey,
  credentialLabel: '~/.ssh/id_ed25519',
  defaultPath: '~',
  status: domain.ConnectionStatus.offline,
  color: domain.ProfileColor.green,
);

void main() {
  Future<(SftpWorkspaceController, FakeSftpBackend, List<String>)> attach({
    required bool fixed,
  }) async {
    final backend = FakeSftpBackend()
      ..nextConnectError = StateError(
        'host key for 10.0.0.11:22 is not in known_hosts (SHA256:abc)',
      );
    final manager = SftpManager(
      backend: backend,
      credentials: ProfileCredentials(),
    );
    addTearDown(manager.dispose);
    final asked = <String>[];
    final controller = SftpWorkspaceController(
      sftpManager: manager,
      resolveConnectFailure: (profile, error) async {
        asked.add('${profile.host}: $error');
        return fixed;
      },
    );
    addTearDown(controller.dispose);
    await controller.attachRemoteProfile(_profile, '/srv');
    return (controller, backend, asked);
  }

  test(
    'a connect failure the UI fixes (e.g. host key trusted) reconnects',
    () async {
      final (controller, backend, asked) = await attach(fixed: true);

      expect(asked, hasLength(1));
      expect(asked.single, contains('not in known_hosts'));
      expect(backend.connected, hasLength(1), reason: 'connected on the retry');
      expect(controller.isRemoteConnected, isTrue);
    },
  );

  test('a connect failure the UI cannot fix shows the error', () async {
    final (controller, backend, asked) = await attach(fixed: false);

    expect(asked, hasLength(1));
    expect(backend.connected, isEmpty);
    expect(controller.remoteStatus, 'failed');
    expect(controller.remoteError, contains('not in known_hosts'));
  });
}
