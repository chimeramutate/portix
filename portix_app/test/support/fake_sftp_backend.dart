import 'dart:io';

import 'package:portix/src/connection_manager/ssh_profile.dart';
import 'package:portix/src/sftp_client/sftp_backend.dart';
import 'package:portix/src/sftp_client/sftp_models.dart';

/// In-memory SFTP server: files live in [remoteFiles]; folders list empty.
class FakeSftpBackend implements SftpBackend {
  final Map<String, List<int>> remoteFiles = {};
  final List<String> downloadCalls = [];
  final Set<String> readErrorPaths = {};
  final Set<String> _alive = {};
  final List<SshProfile> connected = [];

  /// Thrown by the next [connect] instead of connecting, then cleared.
  Object? nextConnectError;
  int _sessionCounter = 0;

  /// Simulates the connection dropping (the server goes away).
  void drop(String? sessionId) => _alive.remove(sessionId);

  @override
  Future<String> connect(SshProfile profile) async {
    final error = nextConnectError;
    nextConnectError = null;
    if (error != null) throw error;
    connected.add(profile);
    final id = 'fake-sftp-${++_sessionCounter}';
    _alive.add(id);
    return id;
  }

  @override
  Future<void> disconnect(String sessionId) async => _alive.remove(sessionId);

  @override
  Future<bool> isAlive(String sessionId) async => _alive.contains(sessionId);

  @override
  Future<String> resolve(String sessionId, String path) async => path;

  @override
  Future<List<RemoteFileEntry>> list(String sessionId, String path) async =>
      const [];

  @override
  Future<List<int>> read(String sessionId, String path) async =>
      List<int>.from(remoteFiles[path] ?? (throw StateError('missing $path')));

  @override
  Future<void> write(String sessionId, String path, List<int> data) async =>
      remoteFiles[path] = List<int>.from(data);

  @override
  Future<void> createDir(String sessionId, String path) async {}

  @override
  Future<void> createFile(String sessionId, String path) async =>
      remoteFiles.putIfAbsent(path, () => <int>[]);

  @override
  Future<void> chmod(String sessionId, String path, int mode) async {}

  @override
  Future<void> rename(String sessionId, String from, String to) async =>
      remoteFiles[to] = remoteFiles.remove(from) ?? const [];

  @override
  Future<void> remove(String sessionId, String path) async =>
      remoteFiles.remove(path);

  @override
  Future<void> copy(String sessionId, String from, String to) async =>
      remoteFiles[to] = List<int>.from(remoteFiles[from] ?? const []);

  @override
  Stream<TransferProgress> download(
    String sessionId,
    String remotePath,
    String localPath,
  ) async* {
    downloadCalls.add(remotePath);
    if (readErrorPaths.contains(remotePath)) {
      throw StateError('simulated remote read failure for $remotePath');
    }
    final data = remoteFiles[remotePath];
    if (data == null) throw StateError('remote file missing: $remotePath');
    await File(localPath).writeAsBytes(data);
    yield TransferProgress(data.length, data.length);
  }

  @override
  Stream<TransferProgress> upload(
    String sessionId,
    String localPath,
    String remotePath,
  ) async* {
    final data = await File(localPath).readAsBytes();
    remoteFiles[remotePath] = data;
    yield TransferProgress(data.length, data.length);
  }
}
