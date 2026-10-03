import '../connection_manager/ssh_profile.dart';
import 'sftp_models.dart';

/// File access over SFTP. Each session is its own SSH connection, separate
/// from terminal sessions. Paths may start with `~` (the login folder).
abstract interface class SftpBackend {
  /// Connects (credentials already resolved) and returns the session id.
  Future<String> connect(SshProfile profile);
  Future<void> disconnect(String sessionId);

  /// False once the connection dropped.
  Future<bool> isAlive(String sessionId);

  Future<String> resolve(String sessionId, String path);
  Future<List<RemoteFileEntry>> list(String sessionId, String path);
  Future<List<int>> read(String sessionId, String path);

  /// Overwrites in place, keeping the file's permissions.
  Future<void> write(String sessionId, String path, List<int> data);
  Future<void> createDir(String sessionId, String path);
  Future<void> createFile(String sessionId, String path);
  Future<void> chmod(String sessionId, String path, int mode);
  Future<void> rename(String sessionId, String from, String to);

  /// Deletes a file or a whole folder.
  Future<void> remove(String sessionId, String path);

  /// Copies a file or folder on the server.
  Future<void> copy(String sessionId, String from, String to);

  /// Progress until done; errors arrive on the stream. Cancelling the
  /// subscription stops the transfer. An interrupted transfer of the same
  /// file resumes where it stopped.
  Stream<TransferProgress> download(
    String sessionId,
    String remotePath,
    String localPath,
  );
  Stream<TransferProgress> upload(
    String sessionId,
    String localPath,
    String remotePath,
  );
}
