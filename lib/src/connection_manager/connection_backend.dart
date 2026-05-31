import 'dart:async';

import 'session_models.dart';
import 'ssh_profile.dart';

abstract interface class ConnectionBackend {
  Stream<TerminalOutputEvent> get terminalOutputStream;
  Stream<ConnectionStatusEvent> get connectionStatusStream;
  Stream<String> get errorEventStream;

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
}
