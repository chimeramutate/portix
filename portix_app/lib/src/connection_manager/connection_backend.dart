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
  Future<String> resolveRemoteDirectory(String sessionId, String path);
  Future<List<RemoteFileEntry>> listRemoteDirectory(
    String sessionId,
    String path,
  );
  Future<String> readRemoteFile(String sessionId, String path);
  Future<List<int>> readRemoteFileBytes(String sessionId, String path);
  Future<void> writeRemoteFile(String sessionId, String path, String content);
  Future<void> uploadRemoteFile(String sessionId, String path, List<int> data);
  Future<void> createRemoteDirectory(String sessionId, String path);
  Future<void> createRemoteFile(String sessionId, String path);
  Future<void> chmodRemotePath(String sessionId, String path, String mode);

  /// Execute an arbitrary remote command on the session's *dedicated exec*
  /// channel (a separate SSH channel, not the interactive shell). The raw
  /// stdout is returned; a non-zero exit status is surfaced as an exception.
  /// Used for SFTP/file-manager file-management operations so they never reach
  /// the interactive shell and therefore never pollute the remote shell
  /// history or the visible terminal.
  Future<String> execRemoteCommand(String sessionId, String command);

  /// Forwards 127.0.0.1:[localPort] (0 = any free port) to [remoteHost]:
  /// [remotePort] over a dedicated SSH connection to [profile].
  Future<PortForward> startLocalForward(
    SshProfile profile,
    int localPort,
    String remoteHost,
    int remotePort,
  );

  Future<void> stopLocalForward(String id);

  /// Tunnels still running; one ends on its own if its SSH connection drops.
  Future<List<PortForward>> listLocalForwards();

  /// The host key refused during the last connect to [host]:[port], if any.
  Future<HostKeyInfo?> pendingHostKey(String host, int port);

  /// Records the refused key of an unknown host after the user confirmed
  /// [fingerprint]. Throws for a changed key or a stale fingerprint.
  Future<void> trustHostKey(String host, int port, String fingerprint);
}
