import 'dart:async';

import 'connection_backend.dart';
import 'session_models.dart';
import 'ssh_profile.dart';

class MockConnectionBackend implements ConnectionBackend {
  final _output = StreamController<TerminalOutputEvent>.broadcast();
  final _status = StreamController<ConnectionStatusEvent>.broadcast();
  final _errors = StreamController<String>.broadcast();

  @override
  Stream<TerminalOutputEvent> get terminalOutputStream => _output.stream;

  @override
  Stream<ConnectionStatusEvent> get connectionStatusStream => _status.stream;

  @override
  Stream<String> get errorEventStream => _errors.stream;

  @override
  Future<String> connect(SshProfile profile) async {
    final sessionId = 'local-${DateTime.now().microsecondsSinceEpoch}';
    _status.add(
      ConnectionStatusEvent(
        sessionId: sessionId,
        status: ConnectionStatus.connecting,
        message: 'Connecting to ${profile.host}:${profile.port}',
      ),
    );
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 500), () {
        if (_status.isClosed || _output.isClosed) return;
        _status.add(
          ConnectionStatusEvent(
            sessionId: sessionId,
            status: ConnectionStatus.connected,
            message: 'Connected',
          ),
        );
        _output.add(
          TerminalOutputEvent(
            sessionId: sessionId,
            data: '${profile.username}@${profile.name}:~\$ ',
          ),
        );
      }),
    );
    return sessionId;
  }

  @override
  Future<void> disconnect(String sessionId) async {
    _output.add(
      TerminalOutputEvent(sessionId: sessionId, data: '\r\n[disconnected]\r\n'),
    );
    _status.add(
      ConnectionStatusEvent(
        sessionId: sessionId,
        status: ConnectionStatus.disconnected,
      ),
    );
  }

  @override
  Future<void> resizeTerminal(String sessionId, int cols, int rows) async {}

  @override
  Future<RemoteSystemSnapshot> remoteSystemSnapshot(String sessionId) async {
    throw UnsupportedError(
      'Remote telemetry is available only on Rust backend',
    );
  }

  @override
  Future<String> resolveRemoteDirectory(String sessionId, String path) async {
    return path;
  }

  @override
  Future<List<RemoteFileEntry>> listRemoteDirectory(
    String sessionId,
    String path,
  ) async {
    throw UnsupportedError('Remote folders are available only on Rust backend');
  }

  @override
  Future<String> readRemoteFile(String sessionId, String path) async {
    throw UnsupportedError('Remote files are available only on Rust backend');
  }

  @override
  Future<List<int>> readRemoteFileBytes(String sessionId, String path) async {
    throw UnsupportedError('Remote files are available only on Rust backend');
  }

  @override
  Future<void> writeRemoteFile(
    String sessionId,
    String path,
    String content,
  ) async {
    throw UnsupportedError('Remote files are available only on Rust backend');
  }

  @override
  Future<void> uploadRemoteFile(
    String sessionId,
    String path,
    List<int> data,
  ) async {
    throw UnsupportedError('Remote upload is available only on Rust backend');
  }

  @override
  Future<void> createRemoteDirectory(String sessionId, String path) async {
    throw UnsupportedError('Remote folders are available only on Rust backend');
  }

  @override
  Future<void> createRemoteFile(String sessionId, String path) async {
    throw UnsupportedError('Remote files are available only on Rust backend');
  }

  @override
  Future<void> chmodRemotePath(
    String sessionId,
    String path,
    String mode,
  ) async {
    throw UnsupportedError('Remote chmod is available only on Rust backend');
  }

  @override
  Future<void> sendTerminalInput(String sessionId, String data) async {
    for (final char in data.codeUnits) {
      switch (char) {
        case 8: // Ctrl+H / backspace
        case 127: // DEL / delete as sent by most terminals
          _output.add(TerminalOutputEvent(sessionId: sessionId, data: '\b \b'));
        case 13: // carriage return
          _output.add(
            TerminalOutputEvent(sessionId: sessionId, data: '\r\n\$ '),
          );
        default:
          _output.add(
            TerminalOutputEvent(
              sessionId: sessionId,
              data: String.fromCharCode(char),
            ),
          );
      }
    }
  }

  void dispose() {
    _output.close();
    _status.close();
    _errors.close();
  }
}
