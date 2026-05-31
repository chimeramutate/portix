import '../../../connection_manager/session_models.dart';
import '../../../connection_manager/ssh_profile.dart';
import '../../../core/result/either.dart';

abstract interface class WorkspaceSessionService {
  List<SshProfile> get profiles;
  List<TerminalSession> get sessions;
  Stream<TerminalOutputEvent> get terminalOutputStream;
  Stream<String> get errorEventStream;

  Result<void> upsertProfile(SshProfile profile);
  Result<void> deleteProfile(String id);
  SshProfile newProfile();

  Future<Result<void>> connect(SshProfile profile);
  Future<Result<void>> connectSftp(SshProfile profile);
  Future<Result<void>> closeSession(String sessionId);
  Future<Result<void>> sendTerminalInput(String sessionId, String data);
  Future<Result<void>> resizeTerminal(String sessionId, int cols, int rows);
  Future<Result<RemoteSystemSnapshot>> remoteSystemSnapshot(String sessionId);
  Future<Result<String>> resolveRemoteDirectory(String sessionId, String path);
  Future<Result<List<RemoteFileEntry>>> listRemoteDirectory(
    String sessionId,
    String path,
  );
  Future<Result<String>> readRemoteFile(String sessionId, String path);
  Future<Result<List<int>>> readRemoteFileBytes(String sessionId, String path);
  Future<Result<void>> writeRemoteFile(
    String sessionId,
    String path,
    String content,
  );
  Future<Result<void>> uploadRemoteFile(
    String sessionId,
    String path,
    List<int> data,
  );
  Future<Result<void>> createRemoteDirectory(String sessionId, String path);
  Future<Result<void>> createRemoteFile(String sessionId, String path);
  Future<Result<void>> chmodRemotePath(
    String sessionId,
    String path,
    String mode,
  );
}
