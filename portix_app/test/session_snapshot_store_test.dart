import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/connection_manager/connection_manager.dart';
import 'package:portix/src/connection_manager/ssh_profile.dart';
import 'package:portix/src/features/ssh_sessions/controller/session_snapshot_store.dart';
import 'package:xterm/xterm.dart';

void main() {
  test('snapshot text joins soft-wrapped lines and drops trailing blanks', () {
    final terminal = Terminal()..resize(10, 24);
    terminal.write('short\r\n0123456789abcdef\r\nlast\r\n\r\n');
    expect(terminalSnapshotText(terminal), 'short\n0123456789abcdef\nlast');
  });

  test('store saves newest first, replaces by id, and deletes', () async {
    final dir = await Directory.systemTemp.createTemp('portix-snapshots');
    addTearDown(() => dir.delete(recursive: true));
    final store = SessionSnapshotStore(
      file: () async => File('${dir.path}/nested/snapshots.json'),
    );
    expect(await store.load(), isEmpty);

    SessionSnapshot snap(String id, int minute, String output) =>
        SessionSnapshot(
          id: id,
          profileId: 'p1',
          title: 'tab $id',
          savedAt: DateTime.utc(2026, 10, 3, 10, minute),
          output: output,
        );
    await store.save(snap('a', 1, 'one'));
    await store.save(snap('b', 2, 'two'));
    await store.save(snap('a', 3, 'one again'));

    var loaded = await store.load();
    expect(loaded.map((s) => s.id), ['a', 'b']);
    expect(loaded.first.output, 'one again');

    await store.delete('a');
    loaded = await store.load();
    expect(loaded.map((s) => s.id), ['b']);
  });

  test('restored text is shown dimmed with CRLF line breaks', () {
    final text = restoredSnapshotText(
      SessionSnapshot(
        id: 'x',
        profileId: 'p',
        title: 'deploy',
        savedAt: DateTime.utc(2026),
        output: 'a\nb',
      ),
    );
    expect(text, contains('a\r\nb\r\n'));
    expect(text, startsWith('\x1b[2m'));
    expect(text, endsWith('\x1b[0m\r\n'));
  });

  test('renameSession renames a tab and ignores blank names', () async {
    final manager = ConnectionManager();
    addTearDown(manager.dispose);
    await manager.connect(
      const SshProfile(
        id: 'p1',
        name: 'web',
        host: 'example.test',
        port: 22,
        username: 'me',
      ),
    );
    final id = manager.sessions.single.id;
    manager.renameSession(id, '  logs  ');
    expect(manager.sessions.single.title, 'logs');
    manager.renameSession(id, '   ');
    expect(manager.sessions.single.title, 'logs');
  });
}
