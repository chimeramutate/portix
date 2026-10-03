import 'dart:async';

import 'connection_backend.dart';
import 'session_models.dart';
import 'ssh_profile.dart';

class UnavailableConnectionBackend implements ConnectionBackend {
  UnavailableConnectionBackend(this.cause);

  final Object cause;
  final _output = StreamController<TerminalOutputEvent>.broadcast();
  final _status = StreamController<ConnectionStatusEvent>.broadcast();
  final _errors = StreamController<ConnectionErrorEvent>.broadcast();

  @override
  Stream<TerminalOutputEvent> get terminalOutputStream => _output.stream;

  @override
  Stream<ConnectionStatusEvent> get connectionStatusStream => _status.stream;

  @override
  Stream<ConnectionErrorEvent> get errorEventStream => _errors.stream;

  Never _unavailable() {
    throw StateError(
      'Rust SSH backend is unavailable. Start Portix with the Rust bridge enabled. Cause: $cause',
    );
  }

  @override
  Future<String> connect(SshProfile profile) async => _unavailable();

  @override
  Future<void> disconnect(String sessionId) async {}

  @override
  Future<void> sendTerminalInput(String sessionId, String data) async =>
      _unavailable();

  @override
  Future<void> resizeTerminal(String sessionId, int cols, int rows) async {}

  @override
  Future<RemoteSystemSnapshot> remoteSystemSnapshot(String sessionId) async =>
      _unavailable();

  @override
  Future<HostKeyInfo?> pendingHostKey(String host, int port) async => null;

  @override
  Future<void> trustHostKey(String host, int port, String fingerprint) async {}

  @override
  Future<PortForward> startLocalForward(
    SshProfile profile,
    int localPort,
    String remoteHost,
    int remotePort,
  ) async => _unavailable();

  @override
  Future<PortForward> startSocksProxy(
    SshProfile profile,
    int localPort,
  ) async => _unavailable();

  @override
  Future<void> stopLocalForward(String id) async {}

  @override
  Future<List<PortForward>> listLocalForwards() async => const [];
}
