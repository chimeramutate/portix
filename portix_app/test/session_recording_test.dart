import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/connection_manager/connection_manager.dart';
import 'package:portix/src/connection_manager/mock_backend.dart';
import 'package:portix/src/connection_manager/ssh_profile.dart';

const _profile = SshProfile(
  id: 'p',
  name: 'box',
  host: 'box.example',
  port: 22,
  username: 'me',
  password: 'secret',
);

void main() {
  test('stripTerminalEscapes keeps only readable text', () {
    expect(
      stripTerminalEscapes(
        '\x1b]0;title\x07\x1b[1;32mok\x1b[0m\r\n\x1b(Bdone\x1b=',
      ),
      'ok\ndone',
    );
  });

  test('records plain output until stopped, then appends nothing', () async {
    final dir = await Directory.systemTemp.createTemp('portix-log');
    addTearDown(() => dir.delete(recursive: true));
    final manager = ConnectionManager(backend: MockConnectionBackend());
    addTearDown(manager.dispose);

    expect((await manager.connect(_profile)).isRight, isTrue);
    final sessionId = manager.sessions.single.id;
    final path = '${dir.path}/nested/box.log';

    manager.startRecording(sessionId, path);
    expect(manager.recordingPath(sessionId), path);
    await manager.sendTerminalInput(sessionId, 'ls\r');
    await pumpEventQueue();
    await manager.stopRecording(sessionId);
    expect(manager.recordingPath(sessionId), isNull);

    await manager.sendTerminalInput(sessionId, 'x');
    await pumpEventQueue();
    expect(File(path).readAsStringSync(), 'ls\n\$ ');
  });
}
