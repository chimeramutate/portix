import 'dart:async';

import 'connection_backend.dart';
import 'session_models.dart';
import 'ssh_profile.dart';

class MockConnectionBackend implements ConnectionBackend {
  final _output = StreamController<TerminalOutputEvent>.broadcast();
  final _status = StreamController<ConnectionStatusEvent>.broadcast();
  final _errors = StreamController<ConnectionErrorEvent>.broadcast();

  @override
  Stream<TerminalOutputEvent> get terminalOutputStream => _output.stream;

  @override
  Stream<ConnectionStatusEvent> get connectionStatusStream => _status.stream;

  @override
  Stream<ConnectionErrorEvent> get errorEventStream => _errors.stream;

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

  @override
  Future<HostKeyInfo?> pendingHostKey(String host, int port) async => null;

  @override
  Future<void> trustHostKey(String host, int port, String fingerprint) async {}

  final List<PortForward> _forwards = [];

  @override
  Future<PortForward> startLocalForward(
    SshProfile profile,
    int localPort,
    String remoteHost,
    int remotePort,
  ) async {
    final forward = PortForward(
      id: 'forward-${_forwards.length + 1}',
      profileId: profile.id,
      localPort: localPort == 0 ? 40000 + _forwards.length : localPort,
      remoteHost: remoteHost,
      remotePort: remotePort,
    );
    _forwards.add(forward);
    return forward;
  }

  @override
  Future<PortForward> startSocksProxy(SshProfile profile, int localPort) async {
    final forward = PortForward(
      id: 'forward-${_forwards.length + 1}',
      profileId: profile.id,
      localPort: localPort == 0 ? 40000 + _forwards.length : localPort,
      remoteHost: '',
      remotePort: 0,
      socks: true,
    );
    _forwards.add(forward);
    return forward;
  }

  @override
  Future<PortForward> startRemoteForward(
    SshProfile profile,
    int remotePort,
    String localHost,
    int localPort,
  ) async {
    final forward = PortForward(
      id: 'forward-${_forwards.length + 1}',
      profileId: profile.id,
      localPort: localPort,
      remoteHost: localHost,
      remotePort: remotePort == 0 ? 50000 + _forwards.length : remotePort,
      reverse: true,
    );
    _forwards.add(forward);
    return forward;
  }

  @override
  Future<void> stopLocalForward(String id) async =>
      _forwards.removeWhere((forward) => forward.id == id);

  @override
  Future<List<PortForward>> listLocalForwards() async => List.of(_forwards);
}
