import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/connection_manager/connection_manager.dart';
import 'package:portix/src/connection_manager/mock_backend.dart';
import 'package:portix/src/connection_manager/profile_credentials.dart';
import 'package:portix/src/connection_manager/ssh_profile.dart';

class _RecordingBackend extends MockConnectionBackend {
  final List<String> disconnected = [];

  @override
  Future<void> disconnect(String sessionId) {
    disconnected.add(sessionId);
    return super.disconnect(sessionId);
  }
}

const _profile = SshProfile(
  id: 'p',
  name: 'p',
  host: 'db.example',
  port: 22,
  username: 'deploy',
  password: 'pw',
);

void main() {
  test('shutdown disconnects every session and stops every forward', () async {
    final backend = _RecordingBackend();
    final manager = ConnectionManager(
      backend: backend,
      credentials: ProfileCredentials(savedProfiles: () async => const []),
    );
    addTearDown(manager.dispose);

    expect((await manager.connect(_profile)).isRight, isTrue);
    expect((await manager.connect(_profile)).isRight, isTrue);
    await manager.startLocalForward(
      _profile,
      localPort: 0,
      remoteHost: 'localhost',
      remotePort: 5432,
    );
    await manager.startSocksProxy(_profile, localPort: 0);

    await manager.shutdown();

    expect(backend.disconnected, hasLength(2));
    expect(await manager.listLocalForwards(), isEmpty);
  });
}
