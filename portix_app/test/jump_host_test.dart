import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/connection_manager/connection_manager.dart';
import 'package:portix/src/connection_manager/profile_credentials.dart';
import 'package:portix/src/connection_manager/mock_backend.dart';
import 'package:portix/src/connection_manager/session_models.dart';
import 'package:portix/src/connection_manager/ssh_profile.dart';
import 'package:portix/src/domain/entities/ssh/index.dart' as domain;
import 'package:portix/src/features/ssh_sessions/widget/remote/host_key_dialog.dart';

class _JumpBackend extends MockConnectionBackend {
  final List<SshProfile> connected = [];
  final List<String> trusted = [];

  @override
  Future<String> connect(SshProfile profile) {
    connected.add(profile);
    return super.connect(profile);
  }

  /// Only the bastion's key is refused.
  @override
  Future<HostKeyInfo?> pendingHostKey(String host, int port) async =>
      host == '127.0.0.1'
      ? const HostKeyInfo(algorithm: 'ssh-ed25519', fingerprint: 'SHA256:j')
      : null;

  @override
  Future<void> trustHostKey(String host, int port, String fingerprint) async =>
      trusted.add('$host:$port $fingerprint');
}

domain.SshProfile _saved(
  String id, {
  String host = '127.0.0.1',
  int port = 22,
  String jump = '',
}) => domain.SshProfile(
  id: id,
  name: id,
  host: host,
  port: port,
  username: 'u',
  group: 'g',
  tags: const [],
  authMethod: domain.AuthMethod.password,
  credentialLabel: 'pw-$id',
  defaultPath: '~',
  status: domain.ConnectionStatus.offline,
  color: domain.ProfileColor.cyan,
  jumpProfileId: jump,
);

void main() {
  test(
    'connects through the jump host and probes it, not the target',
    () async {
      final bastion = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(bastion.close);
      final backend = _JumpBackend();
      final manager = ConnectionManager(
        backend: backend,
        credentials: ProfileCredentials(
          savedProfiles: () async => [_saved('bastion', port: bastion.port)],
        ),
      );
      addTearDown(manager.dispose);

      final target = SshProfile.fromDomain(
        _saved('db', host: 'db.invalid', jump: 'bastion'),
      );
      expect((await manager.connect(target)).isRight, isTrue);

      final sent = backend.connected.single;
      expect(sent.host, 'db.invalid');
      expect(sent.password, 'pw-db');
      expect(sent.jumpHost?.host, '127.0.0.1');
      expect(sent.jumpHost?.password, 'pw-bastion');
      expect(
        await manager.isSessionHostReachable(manager.sessions.single.id),
        isTrue,
      );
    },
  );

  test('missing or looping jump hosts fail before connecting', () async {
    final backend = _JumpBackend();
    final manager = ConnectionManager(
      backend: backend,
      credentials: ProfileCredentials(
        savedProfiles: () async => [
          _saved('a', jump: 'b'),
          _saved('b', jump: 'a'),
        ],
      ),
    );
    addTearDown(manager.dispose);

    final loop = await manager.connect(
      SshProfile.fromDomain(_saved('a', jump: 'b')),
    );
    final missing = await manager.connect(
      SshProfile.fromDomain(_saved('c', jump: 'gone')),
    );
    expect(loop.isLeft, isTrue);
    expect(missing.isLeft, isTrue);
    expect(backend.connected, isEmpty);
  });

  testWidgets('host key prompt targets the jump host that refused it', (
    tester,
  ) async {
    final backend = _JumpBackend();
    final manager = ConnectionManager(
      backend: backend,
      credentials: ProfileCredentials(
        savedProfiles: () async => [_saved('bastion', port: 2200)],
      ),
    );
    final target = SshProfile.fromDomain(
      _saved('db', host: 'db.invalid', jump: 'bastion'),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => resolveRefusedHostKey(context, manager, target),
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.textContaining('[127.0.0.1]:2200'), findsWidgets);
    await tester.tap(find.text('Trust and connect'));
    await tester.pumpAndSettle();
    expect(backend.trusted, ['127.0.0.1:2200 SHA256:j']);
    manager.dispose();
  });
}
