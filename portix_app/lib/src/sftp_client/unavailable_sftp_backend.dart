import '../connection_manager/ssh_profile.dart';
import 'sftp_backend.dart';
import 'sftp_models.dart';

/// Used without the Rust library (mock mode, mobile): every call explains
/// why file access is unavailable.
class UnavailableSftpBackend implements SftpBackend {
  const UnavailableSftpBackend(this.cause);

  final Object cause;

  Never _unavailable() =>
      throw UnsupportedError('SFTP needs the Rust backend. Cause: $cause');

  @override
  Future<String> connect(SshProfile profile) async => _unavailable();
  @override
  Future<void> disconnect(String sessionId) async {}
  @override
  Future<bool> isAlive(String sessionId) async => false;
  @override
  Future<String> resolve(String sessionId, String path) async => _unavailable();
  @override
  Future<List<RemoteFileEntry>> list(String sessionId, String path) async =>
      _unavailable();
  @override
  Future<List<int>> read(String sessionId, String path) async => _unavailable();
  @override
  Future<void> write(String sessionId, String path, List<int> data) async =>
      _unavailable();
  @override
  Future<void> createDir(String sessionId, String path) async => _unavailable();
  @override
  Future<void> createFile(String sessionId, String path) async =>
      _unavailable();
  @override
  Future<void> chmod(String sessionId, String path, int mode) async =>
      _unavailable();
  @override
  Future<void> rename(String sessionId, String from, String to) async =>
      _unavailable();
  @override
  Future<void> remove(String sessionId, String path) async => _unavailable();
  @override
  Future<void> copy(String sessionId, String from, String to) async =>
      _unavailable();
  @override
  Stream<TransferProgress> download(
    String sessionId,
    String remotePath,
    String localPath,
  ) => Stream.error(UnsupportedError('SFTP needs the Rust backend: $cause'));
  @override
  Stream<TransferProgress> upload(
    String sessionId,
    String localPath,
    String remotePath,
  ) => Stream.error(UnsupportedError('SFTP needs the Rust backend: $cause'));
}
