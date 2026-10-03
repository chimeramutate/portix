import 'dart:async';

import 'session_models.dart';
import 'ssh_profile.dart';

abstract interface class ConnectionBackend {
  Stream<TerminalOutputEvent> get terminalOutputStream;
  Stream<ConnectionStatusEvent> get connectionStatusStream;
  Stream<ConnectionErrorEvent> get errorEventStream;

  Future<String> connect(SshProfile profile);
  Future<void> disconnect(String sessionId);
  Future<void> sendTerminalInput(String sessionId, String data);
  Future<void> resizeTerminal(String sessionId, int cols, int rows);
  Future<RemoteSystemSnapshot> remoteSystemSnapshot(String sessionId);

  /// Forwards 127.0.0.1:[localPort] (0 = any free port) to [remoteHost]:
  /// [remotePort] over a dedicated SSH connection to [profile].
  Future<PortForward> startLocalForward(
    SshProfile profile,
    int localPort,
    String remoteHost,
    int remotePort,
  );

  /// Serves a SOCKS5 proxy on 127.0.0.1:[localPort] (0 = any free port);
  /// connections go wherever each client asks, from [profile]'s server.
  Future<PortForward> startSocksProxy(SshProfile profile, int localPort);

  Future<void> stopLocalForward(String id);

  /// Tunnels still running; one ends on its own if its SSH connection drops.
  Future<List<PortForward>> listLocalForwards();

  /// The host key refused during the last connect to [host]:[port], if any.
  Future<HostKeyInfo?> pendingHostKey(String host, int port);

  /// Records the refused key of an unknown host after the user confirmed
  /// [fingerprint]. Throws for a changed key or a stale fingerprint.
  Future<void> trustHostKey(String host, int port, String fingerprint);
}
