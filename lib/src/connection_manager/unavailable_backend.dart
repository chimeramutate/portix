import 'dart:async';

import 'connection_backend.dart';
import 'session_models.dart';
import 'ssh_profile.dart';

class UnavailableConnectionBackend implements ConnectionBackend {
  UnavailableConnectionBackend(this.cause);

  final Object cause;
  final _output = StreamController<TerminalOutputEvent>.broadcast();
  final _status = StreamController<ConnectionStatusEvent>.broadcast();
  final _errors = StreamController<String>.broadcast();

  @override
  Stream<TerminalOutputEvent> get terminalOutputStream => _output.stream;

  @override
  Stream<ConnectionStatusEvent> get connectionStatusStream => _status.stream;

  @override
  Stream<String> get errorEventStream => _errors.stream;

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
  Future<String> resolveRemoteDirectory(String sessionId, String path) async =>
      _unavailable();

  @override
  Future<List<RemoteFileEntry>> listRemoteDirectory(
    String sessionId,
    String path,
  ) async => _unavailable();

  @override
  Future<String> readRemoteFile(String sessionId, String path) async =>
      _unavailable();

  @override
  Future<List<int>> readRemoteFileBytes(String sessionId, String path) async =>
      _unavailable();

  @override
  Future<void> writeRemoteFile(
    String sessionId,
    String path,
    String content,
  ) async => _unavailable();

  @override
  Future<void> uploadRemoteFile(
    String sessionId,
    String path,
    List<int> data,
  ) async => _unavailable();

  @override
  Future<void> createRemoteDirectory(String sessionId, String path) async =>
      _unavailable();

  @override
  Future<void> createRemoteFile(String sessionId, String path) async =>
      _unavailable();

  @override
  Future<void> chmodRemotePath(
    String sessionId,
    String path,
    String mode,
  ) async => _unavailable();
}
