import '../connection_manager/rust_bridge_backend.dart' show toRustProfile;
import '../connection_manager/ssh_profile.dart';
import '../rust/api/sftp.dart' as rust;
import '../rust/domain/sftp.dart' as rust_sftp;
import 'sftp_backend.dart';
import 'sftp_models.dart';

/// Requires the Rust library to be loaded (done by `RustBridgeBackend`).
class RustSftpBackend implements SftpBackend {
  const RustSftpBackend();

  @override
  Future<String> connect(SshProfile profile) =>
      rust.sftpConnect(profile: toRustProfile(profile));

  @override
  Future<void> disconnect(String sessionId) =>
      rust.sftpDisconnect(sessionId: sessionId);

  @override
  Future<bool> isAlive(String sessionId) =>
      rust.sftpIsAlive(sessionId: sessionId);

  @override
  Future<String> resolve(String sessionId, String path) =>
      rust.sftpResolve(sessionId: sessionId, path: path);

  @override
  Future<List<RemoteFileEntry>> list(String sessionId, String path) async =>
      (await rust.sftpList(sessionId: sessionId, path: path))
          .map(
            (entry) => RemoteFileEntry(
              name: entry.name,
              path: entry.path,
              isDirectory: entry.isDirectory,
              sizeBytes: entry.sizeBytes.toInt(),
              modifiedUnixSeconds: entry.modifiedUnixSeconds.toInt(),
              mode: entry.mode,
            ),
          )
          .toList(growable: false);

  @override
  Future<List<int>> read(String sessionId, String path) =>
      rust.sftpRead(sessionId: sessionId, path: path);

  @override
  Future<void> write(String sessionId, String path, List<int> data) =>
      rust.sftpWrite(sessionId: sessionId, path: path, data: data);

  @override
  Future<void> createDir(String sessionId, String path) =>
      rust.sftpCreateDir(sessionId: sessionId, path: path);

  @override
  Future<void> createFile(String sessionId, String path) =>
      rust.sftpCreateFile(sessionId: sessionId, path: path);

  @override
  Future<void> chmod(String sessionId, String path, int mode) =>
      rust.sftpChmod(sessionId: sessionId, path: path, mode: mode);

  @override
  Future<void> rename(String sessionId, String from, String to) =>
      rust.sftpRename(sessionId: sessionId, from: from, to: to);

  @override
  Future<void> remove(String sessionId, String path) =>
      rust.sftpRemove(sessionId: sessionId, path: path);

  @override
  Future<void> copy(String sessionId, String from, String to) =>
      rust.sftpCopy(sessionId: sessionId, from: from, to: to);

  @override
  Stream<TransferProgress> download(
    String sessionId,
    String remotePath,
    String localPath,
  ) => rust
      .sftpDownload(
        sessionId: sessionId,
        remotePath: remotePath,
        localPath: localPath,
      )
      .map(_progress);

  @override
  Stream<TransferProgress> upload(
    String sessionId,
    String localPath,
    String remotePath,
  ) => rust
      .sftpUpload(
        sessionId: sessionId,
        localPath: localPath,
        remotePath: remotePath,
      )
      .map(_progress);

  static TransferProgress _progress(rust_sftp.TransferProgress progress) =>
      TransferProgress(progress.done.toInt(), progress.total.toInt());
}
