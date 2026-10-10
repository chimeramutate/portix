import 'dart:async';

import 'package:flutter/foundation.dart';

import '../connection_manager/profile_credentials.dart';
import '../connection_manager/ssh_profile.dart';
import '../core/result/either.dart';
import 'remote_search.dart';
import 'sftp_backend.dart';
import 'sftp_models.dart';

/// Open SFTP sessions and the file operations on them. Independent of
/// terminal sessions: each SFTP session is its own SSH connection, opened
/// and closed by whoever needs file access.
class SftpManager extends ChangeNotifier {
  SftpManager({
    required SftpBackend backend,
    required this.credentials,
    this.livenessInterval = const Duration(seconds: 5),
  }) : _backend = backend;

  final SftpBackend _backend;
  final ProfileCredentials credentials;

  /// How often connected sessions are checked for a dropped connection, so
  /// an idle file browser notices without the user doing anything.
  final Duration livenessInterval;

  final Map<String, SftpSession> _sessions = {};
  Timer? _livenessTimer;
  bool _disposed = false;

  SftpSession? session(String sessionId) => _sessions[sessionId];

  bool isConnected(String sessionId) =>
      _sessions[sessionId]?.isConnected ?? false;

  /// Connects to [profile] (saved secrets and jump hosts resolved) and
  /// returns the new session id. Failures such as a refused host key or a
  /// missing key passphrase arrive here, as the [Left].
  Future<Result<String>> connect(SshProfile profile) async {
    try {
      final id = await _backend.connect(await credentials.resolve(profile));
      _sessions[id] = SftpSession(id: id, profileId: profile.id);
      _livenessTimer ??= Timer.periodic(livenessInterval, (_) {
        for (final id in _sessions.keys.toList()) {
          unawaited(_checkAlive(id));
        }
      });
      _notify();
      return Right(id);
    } catch (error) {
      return Left(
        AppFailure('Failed to connect to ${profile.name}', cause: error),
      );
    }
  }

  /// Closes every SFTP session; used when the app quits.
  Future<void> shutdown() =>
      Future.wait([for (final id in _sessions.keys.toList()) close(id)]);

  Future<void> close(String sessionId) async {
    if (_sessions.remove(sessionId) != null) _notify();
    if (_sessions.isEmpty) {
      _livenessTimer?.cancel();
      _livenessTimer = null;
    }
    await _backend.disconnect(sessionId).catchError((Object _) {});
  }

  Future<Result<String>> resolve(String sessionId, String path) => _call(
    sessionId,
    'Failed to resolve remote folder',
    () => _backend.resolve(sessionId, path),
  );

  Future<Result<List<RemoteFileEntry>>> list(String sessionId, String path) =>
      _call(
        sessionId,
        'Failed to load remote folder',
        () => _backend.list(sessionId, path),
      );

  /// Entries below [basePath] whose name or path contains [query].
  Future<Result<List<RemoteFileEntry>>> find(
    String sessionId,
    String basePath,
    String query, {
    int maxResults = 120,
  }) async {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return const Right([]);
    return _call(
      sessionId,
      'Failed to find remote entries',
      () => findRemoteEntries(
        list: (path) => _backend.list(sessionId, path),
        basePath: basePath,
        query: normalized,
        maxResults: maxResults,
      ),
    );
  }

  Future<Result<List<int>>> read(String sessionId, String path) => _call(
    sessionId,
    'Failed to read remote file',
    () => _backend.read(sessionId, path),
  );

  Future<Result<void>> write(String sessionId, String path, List<int> data) =>
      _call(
        sessionId,
        'Failed to save remote file',
        () => _backend.write(sessionId, path, data),
      );

  Future<Result<void>> createDir(String sessionId, String path) => _call(
    sessionId,
    'Failed to create remote folder',
    () => _backend.createDir(sessionId, path),
  );

  Future<Result<void>> createFile(String sessionId, String path) => _call(
    sessionId,
    'Failed to create remote file',
    () => _backend.createFile(sessionId, path),
  );

  /// [mode] is octal text like `755`.
  Future<Result<void>> chmod(String sessionId, String path, String mode) {
    final bits = int.tryParse(mode.trim(), radix: 8);
    if (bits == null || bits > 0xFFF) {
      return Future.value(Left(AppFailure('Invalid permission mode: $mode')));
    }
    return _call(
      sessionId,
      'Failed to update permissions',
      () => _backend.chmod(sessionId, path, bits),
    );
  }

  Future<Result<void>> rename(String sessionId, String from, String to) =>
      _call(
        sessionId,
        'Failed to move remote path',
        () => _backend.rename(sessionId, from, to),
      );

  Future<Result<void>> remove(String sessionId, String path) => _call(
    sessionId,
    'Failed to delete remote path',
    () => _backend.remove(sessionId, path),
  );

  Future<Result<void>> copy(String sessionId, String from, String to) => _call(
    sessionId,
    'Failed to duplicate remote path',
    () => _backend.copy(sessionId, from, to),
  );

  /// Downloads a file straight to disk. Retrying after a failure resumes.
  Future<Result<void>> download(
    String sessionId,
    String remotePath,
    String localPath, {
    void Function(TransferProgress progress)? onProgress,
  }) => _call(
    sessionId,
    'Failed to download remote file',
    () => _backend
        .download(sessionId, remotePath, localPath)
        .forEach((progress) => onProgress?.call(progress)),
  );

  /// Uploads a file straight from disk. Retrying after a failure resumes.
  Future<Result<void>> upload(
    String sessionId,
    String localPath,
    String remotePath, {
    void Function(TransferProgress progress)? onProgress,
  }) => _call(
    sessionId,
    'Failed to upload file',
    () => _backend
        .upload(sessionId, localPath, remotePath)
        .forEach((progress) => onProgress?.call(progress)),
  );

  Future<Result<T>> _call<T>(
    String sessionId,
    String failureMessage,
    Future<T> Function() operation,
  ) async {
    try {
      return Right(await operation());
    } catch (error) {
      // A failure may be the connection dropping; find out right away.
      unawaited(_checkAlive(sessionId));
      return Left(AppFailure(failureMessage, cause: error));
    }
  }

  Future<void> _checkAlive(String sessionId) async {
    final session = _sessions[sessionId];
    if (session == null || !session.isConnected) return;
    final alive = await _backend
        .isAlive(sessionId)
        .catchError((Object _) => false);
    if (alive || _sessions[sessionId] != session) return;
    _sessions[sessionId] = SftpSession(
      id: sessionId,
      profileId: session.profileId,
      status: SftpStatus.disconnected,
    );
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _livenessTimer?.cancel();
    for (final id in _sessions.keys) {
      unawaited(_backend.disconnect(id).catchError((Object _) {}));
    }
    _sessions.clear();
    super.dispose();
  }
}

/// One SFTP session per profile for a single owner (e.g. a page), opened on
/// first use and reopened after it drops. The owner calls [closeAll] when
/// done; sessions are never shared with other owners, which close their own.
class SftpSessionPool {
  SftpSessionPool(this._manager);

  final SftpManager _manager;
  final Map<String, Future<Result<String>>> _sessions = {};

  /// A connected session id for [profile]. Concurrent callers share one
  /// connect attempt.
  Future<Result<String>> sessionFor(SshProfile profile) async {
    final pending = _sessions[profile.id];
    final previous = pending == null ? null : await pending;
    final usable = previous?.fold((_) => false, _manager.isConnected) ?? false;
    if (!usable && identical(_sessions[profile.id], pending)) {
      _sessions[profile.id] = _manager.connect(profile);
    }
    return _sessions[profile.id]!;
  }

  void closeAll() {
    for (final pending in _sessions.values) {
      unawaited(pending.then((result) => result.fold((_) {}, _manager.close)));
    }
    _sessions.clear();
  }
}
