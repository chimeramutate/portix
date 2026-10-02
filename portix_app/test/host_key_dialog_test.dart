import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/connection_manager/connection_manager.dart';
import 'package:portix/src/connection_manager/mock_backend.dart';
import 'package:portix/src/connection_manager/session_models.dart';
import 'package:portix/src/connection_manager/ssh_profile.dart';
import 'package:portix/src/features/ssh_sessions/widget/remote/host_key_dialog.dart';

class _HostKeyBackend extends MockConnectionBackend {
  _HostKeyBackend(this.pending);

  HostKeyInfo? pending;
  final List<String> trusted = [];

  @override
  Future<HostKeyInfo?> pendingHostKey(String host, int port) async => pending;

  @override
  Future<void> trustHostKey(String host, int port, String fingerprint) async {
    trusted.add('$host:$port $fingerprint');
  }
}

const _profile = SshProfile(
  id: 'p',
  name: 'p',
  host: 'example.com',
  port: 2222,
  username: 'u',
);

/// Runs [resolveRefusedHostKey] from a button so dialogs have a Navigator.
Future<bool?> _resolve(
  WidgetTester tester,
  ConnectionManager manager, {
  required String tapLabel,
}) async {
  bool? result;
  var done = false;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            result = await resolveRefusedHostKey(context, manager, _profile);
            done = true;
          },
          child: const Text('go'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
  if (tapLabel.isNotEmpty) {
    await tester.tap(find.text(tapLabel));
    await tester.pumpAndSettle();
  }
  expect(done, isTrue);
  return result;
}

void main() {
  testWidgets('no refused key: returns null without a dialog', (tester) async {
    final manager = ConnectionManager(backend: _HostKeyBackend(null));
    expect(await _resolve(tester, manager, tapLabel: ''), isNull);
    manager.dispose();
  });

  testWidgets('unknown host: trusting records the shown fingerprint', (
    tester,
  ) async {
    final backend = _HostKeyBackend(
      const HostKeyInfo(algorithm: 'ssh-ed25519', fingerprint: 'SHA256:abc'),
    );
    final manager = ConnectionManager(backend: backend);
    expect(
      await _resolve(tester, manager, tapLabel: 'Trust and connect'),
      isTrue,
    );
    expect(backend.trusted, ['example.com:2222 SHA256:abc']);
    manager.dispose();
  });

  testWidgets('unknown host: cancel trusts nothing', (tester) async {
    final backend = _HostKeyBackend(
      const HostKeyInfo(algorithm: 'ssh-ed25519', fingerprint: 'SHA256:abc'),
    );
    final manager = ConnectionManager(backend: backend);
    expect(await _resolve(tester, manager, tapLabel: 'Cancel'), isFalse);
    expect(backend.trusted, isEmpty);
    manager.dispose();
  });

  testWidgets('changed key: warns with the removal command, never trusts', (
    tester,
  ) async {
    final backend = _HostKeyBackend(
      const HostKeyInfo(
        algorithm: 'ssh-ed25519',
        fingerprint: 'SHA256:new',
        changedLine: 7,
      ),
    );
    final manager = ConnectionManager(backend: backend);
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await resolveRefusedHostKey(context, manager, _profile);
            },
            child: const Text('go'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
    expect(find.text('Host key changed'), findsOneWidget);
    expect(find.text('ssh-keygen -R "[example.com]:2222"'), findsOneWidget);
    expect(find.text('Trust and connect'), findsNothing);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
    expect(backend.trusted, isEmpty);
    manager.dispose();
  });
}
