import 'dart:async';

import 'package:portix/src/connection_manager/mock_backend.dart';
import 'package:portix/src/connection_manager/session_models.dart';
import 'package:portix/src/connection_manager/ssh_profile.dart';

/// Like the real backend, connect returns a session id first and the host
/// key refusal arrives later as status + error events.
class RefusingHostKeyBackend extends MockConnectionBackend {
  final _status = StreamController<ConnectionStatusEvent>.broadcast();
  final _errors = StreamController<ConnectionErrorEvent>.broadcast();
  final List<String> trusted = [];
  var _connects = 0;

  @override
  Stream<ConnectionStatusEvent> get connectionStatusStream => _status.stream;

  @override
  Stream<ConnectionErrorEvent> get errorEventStream => _errors.stream;

  @override
  Future<String> connect(SshProfile profile) async {
    final id = 'backend-${++_connects}';
    final refused = trusted.isEmpty;
    scheduleMicrotask(() {
      _status.add(
        ConnectionStatusEvent(
          sessionId: id,
          status: refused ? ConnectionStatus.error : ConnectionStatus.connected,
        ),
      );
      if (refused) {
        _errors.add(
          ConnectionErrorEvent(
            sessionId: id,
            message: 'host key for 10.0.0.11:22 is not in known_hosts',
          ),
        );
      }
    });
    return id;
  }

  @override
  Future<HostKeyInfo?> pendingHostKey(String host, int port) async =>
      trusted.isEmpty
      ? const HostKeyInfo(algorithm: 'ssh-ed25519', fingerprint: 'SHA256:abc')
      : null;

  @override
  Future<void> trustHostKey(String host, int port, String fingerprint) async =>
      trusted.add(fingerprint);
}
