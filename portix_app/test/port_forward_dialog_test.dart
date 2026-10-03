import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/connection_manager/connection_manager.dart';
import 'package:portix/src/connection_manager/mock_backend.dart';
import 'package:portix/src/connection_manager/ssh_profile.dart';
import 'package:portix/src/features/ssh_sessions/widget/remote/port_forward_dialog.dart';

const _profile = SshProfile(
  id: 'p',
  name: 'p',
  host: 'db.example',
  port: 22,
  username: 'deploy',
  privateKeyPath: '~/.ssh/id_ed25519',
);

Future<void> _open(WidgetTester tester, ConnectionManager manager) async {
  await tester.binding.setSurfaceSize(const Size(900, 700));
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showPortForwardDialog(context, manager, _profile),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Finder _field(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(Column)).first,
  matching: find.byType(TextField),
);

void main() {
  testWidgets('starts a tunnel, lists it, and stops it', (tester) async {
    final manager = ConnectionManager(backend: MockConnectionBackend());
    await _open(tester, manager);
    expect(find.text('No tunnels running.'), findsOneWidget);

    await tester.enterText(_field('Local port'), '15432');
    await tester.enterText(_field('Remote port'), '5432');
    await tester.tap(find.text('Start tunnel'));
    await tester.pumpAndSettle();

    expect(find.text('127.0.0.1:15432 → 127.0.0.1:5432'), findsOneWidget);

    await tester.tap(find.byTooltip('Stop tunnel'));
    await tester.pumpAndSettle();
    expect(find.text('No tunnels running.'), findsOneWidget);
    manager.dispose();
  });

  testWidgets('rejects an invalid remote port without starting', (
    tester,
  ) async {
    final manager = ConnectionManager(backend: MockConnectionBackend());
    await _open(tester, manager);

    await tester.enterText(_field('Remote port'), '70000');
    await tester.tap(find.text('Start tunnel'));
    await tester.pumpAndSettle();

    expect(find.textContaining('valid ports'), findsOneWidget);
    expect(await manager.listLocalForwards(), isEmpty);
    manager.dispose();
  });

  testWidgets('starts a SOCKS proxy without a remote target', (tester) async {
    final manager = ConnectionManager(backend: MockConnectionBackend());
    await _open(tester, manager);

    await tester.tap(find.text('SOCKS proxy (-D)'));
    await tester.pumpAndSettle();
    expect(find.text('Remote host'), findsNothing);

    await tester.enterText(_field('Local port'), '1080');
    await tester.tap(find.text('Start tunnel'));
    await tester.pumpAndSettle();

    expect(find.text('127.0.0.1:1080 → SOCKS5 proxy'), findsOneWidget);
    expect(find.byTooltip('Copy socks5h://127.0.0.1:1080'), findsOneWidget);
    final forwards = await manager.listLocalForwards();
    expect(forwards.single.socks, isTrue);
    manager.dispose();
  });

  testWidgets('starts a remote forward back to a local port', (tester) async {
    final manager = ConnectionManager(backend: MockConnectionBackend());
    await _open(tester, manager);

    await tester.tap(find.text('Remote (-R)'));
    await tester.pumpAndSettle();
    expect(find.text('Server port'), findsOneWidget);

    // Local port is required in this mode.
    await tester.tap(find.text('Start tunnel'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Enter a local host and port'), findsOneWidget);

    await tester.enterText(_field('Local port'), '3000');
    await tester.tap(find.text('Start tunnel'));
    await tester.pumpAndSettle();

    final forward = (await manager.listLocalForwards()).single;
    expect(forward.reverse, isTrue);
    expect((forward.remoteHost, forward.localPort), ('127.0.0.1', 3000));
    expect(
      find.text('server localhost:${forward.remotePort} → 127.0.0.1:3000'),
      findsOneWidget,
    );
    manager.dispose();
  });
}
