import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/connection_manager/connection_manager.dart';
import 'package:portix/src/connection_manager/session_models.dart';
import 'package:portix/src/domain/entities/ssh/index.dart' as domain;
import 'package:portix/src/features/sftp/controller/sftp_workspace_controller.dart';

import 'support/refusing_host_key_backend.dart';

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
  test(
    'async host key refusal asks the UI, then re-attaches once trusted',
    () async {
      final backend = RefusingHostKeyBackend();
      final manager = ConnectionManager(backend: backend);
      addTearDown(manager.dispose);
      final asked = <String>[];
      final controller = SftpWorkspaceController(
        connectionManager: manager,
        resolveRefusedHostKey: (profile) async {
          asked.add('${profile.host}:${profile.port}');
          final info = await manager.pendingHostKey(profile);
          if (info == null) return null;
          await manager.trustHostKey(profile, info.fingerprint);
          return true;
        },
      );
      addTearDown(controller.dispose);

      await controller.attachRemoteProfile(_profile, '/srv');
      bool reconnected() => manager.sessions.any(
        (session) => session.status == ConnectionStatus.connected,
      );
      for (var i = 0; i < 100 && !reconnected(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      expect(asked, ['10.0.0.11:22']);
      expect(backend.trusted, ['SHA256:abc']);
      expect(reconnected(), isTrue, reason: 're-attached after trusting');
    },
  );
}
