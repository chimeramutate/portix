import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/connection_manager/profile_credentials.dart';
import 'package:portix/src/connection_manager/ssh_profile.dart';
import 'package:portix/src/core/result/either.dart';
import 'package:portix/src/sftp_client/sftp_manager.dart';

import 'support/fake_sftp_backend.dart';

const _profile = SshProfile(
  id: 'p',
  name: 'p',
  host: 'h',
  port: 22,
  username: 'u',
  privateKeyPath: '~/.ssh/id_ed25519',
);

void main() {
  late FakeSftpBackend backend;
  late SftpManager manager;

  setUp(() {
    backend = FakeSftpBackend();
    manager = SftpManager(
      backend: backend,
      credentials: ProfileCredentials(),
      livenessInterval: const Duration(milliseconds: 5),
    );
  });
  tearDown(() => manager.dispose());

  String idOf(Result<String> result) =>
      result.fold((failure) => fail('$failure'), (id) => id);

  test('a dropped connection is noticed without any file operation', () async {
    final id = idOf(await manager.connect(_profile));
    expect(manager.isConnected(id), isTrue);

    backend.drop(id);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(manager.isConnected(id), isFalse);
    expect(manager.session(id), isNotNull, reason: 'kept until closed');
  });

  test('chmod takes octal text and rejects anything else', () async {
    final id = idOf(await manager.connect(_profile));
    expect((await manager.chmod(id, '/f', '755')).isRight, isTrue);
    expect((await manager.chmod(id, '/f', '9z')).isLeft, isTrue);
    expect((await manager.chmod(id, '/f', '17777')).isLeft, isTrue);
  });

  group('SftpSessionPool', () {
    test(
      'shares one connect between concurrent callers, then reuses it',
      () async {
        final pool = SftpSessionPool(manager);
        final ids = await Future.wait([
          pool.sessionFor(_profile),
          pool.sessionFor(_profile),
        ]);
        final again = await pool.sessionFor(_profile);

        expect(backend.connected, hasLength(1));
        expect({idOf(ids[0]), idOf(ids[1]), idOf(again)}, hasLength(1));
      },
    );

    test('reconnects after the session dropped, and closeAll closes', () async {
      final pool = SftpSessionPool(manager);
      final first = idOf(await pool.sessionFor(_profile));
      backend.drop(first);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final second = idOf(await pool.sessionFor(_profile));
      expect(second, isNot(first));

      pool.closeAll();
      await Future<void>.delayed(Duration.zero);
      expect(manager.session(second), isNull);
    });
  });
}
