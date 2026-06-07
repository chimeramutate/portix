import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/result/either.dart';
import '../domain/services/workspace/workspace_session_service.dart';
import 'connection_backend.dart';
import 'mock_backend.dart';
import 'profile_secret_store.dart';
import 'rust_bridge_backend.dart';
import 'session_models.dart';
import 'ssh_profile.dart';

class ConnectionManager extends ChangeNotifier
    implements WorkspaceSessionService {
  ConnectionManager({
    ConnectionBackend? backend,
    ProfileSecretStore? secretStore,
  }) : _backend = backend ?? MockConnectionBackend(),
       _secretStore = secretStore ?? const ProfileSecretStore() {
    _statusSub = _backend.connectionStatusStream.listen(_handleStatus);
    _outputSub = _backend.terminalOutputStream.listen(_handleTerminalOutput);
    _errorSub = _backend.errorEventStream.listen(_handleError);
  }

  final ConnectionBackend _backend;
  final ProfileSecretStore _secretStore;
  final _uuid = const Uuid();
  late final StreamSubscription<ConnectionStatusEvent> _statusSub;
  late final StreamSubscription<TerminalOutputEvent> _outputSub;
  late final StreamSubscription<ConnectionErrorEvent> _errorSub;
  final Map<String, String> _backendToUiSessionIds = {};
  final Map<String, Future<void>> _pendingSecretWrites = {};
  final Map<String, Object> _secretWriteErrors = {};
  final _terminalOutput = StreamController<TerminalOutputEvent>.broadcast();
  final _errors = StreamController<ConnectionErrorEvent>.broadcast();

  final List<SshProfile> _profiles = [];

  final List<TerminalSession> _sessions = [];

  @override
  List<SshProfile> get profiles => List.unmodifiable(_profiles);
  @override
  List<TerminalSession> get sessions => List.unmodifiable(_sessions);
  @override
  Stream<TerminalOutputEvent> get terminalOutputStream =>
      _terminalOutput.stream;
  @override
  Stream<ConnectionErrorEvent> get errorEventStream => _errors.stream;

  @override
  Result<void> upsertProfile(SshProfile profile) {
    try {
      final password = profile.password?.trim();
      if ((profile.privateKeyPath ?? '').trim().isNotEmpty) {
        _queueSecretWrite(profile.id, _secretStore.deletePassword(profile.id));
        profile = profile.copyWith(hasPassword: false, clearPassword: true);
      } else if (password != null && password.isNotEmpty) {
        _queueSecretWrite(
          profile.id,
          _secretStore.savePassword(profile.id, password),
        );
        profile = profile.copyWith(hasPassword: true, clearPassword: true);
      } else {
        profile = profile.copyWith(clearPassword: true);
      }
      final index = _profiles.indexWhere((item) => item.id == profile.id);
      if (index == -1) {
        _profiles.add(profile);
      } else {
        _profiles[index] = profile;
      }
      notifyListeners();
      return const Right(null);
    } catch (error) {
      return Left(AppFailure('Failed to save profile', cause: error));
    }
  }

  @override
  Result<void> deleteProfile(String id) {
    try {
      _profiles.removeWhere((profile) => profile.id == id);
      _queueSecretWrite(id, _secretStore.deletePassword(id));
      notifyListeners();
      return const Right(null);
    } catch (error) {
      return Left(AppFailure('Failed to delete profile', cause: error));
    }
  }

  @override
  SshProfile newProfile() {
    return SshProfile(
      id: _uuid.v4(),
      name: 'New server',
      host: '',
      port: 22,
      username: '',
    );
  }

  @override
  Future<Result<void>> connect(SshProfile profile) async {
    return _connect(profile, kind: SessionKind.ssh);
  }

  @override
  Future<Result<void>> connectSftp(SshProfile profile) async {
    return _connect(
      profile,
      kind: SessionKind.sftp,
      title: 'SFTP ${profile.name}',
    );
  }

  Future<Result<void>> _connect(
    SshProfile profile, {
    required SessionKind kind,
    String? title,
  }) async {
    if (profile.host.trim().isEmpty || profile.username.trim().isEmpty) {
      return const Left(
        AppFailure('Host and username are required before connecting.'),
      );
    }
    final uiSessionId = _uuid.v4();
    final baseTitle = title ?? profile.name;
    final duplicateCount = _sessions
        .where(
          (session) => session.profileId == profile.id && session.kind == kind,
        )
        .length;
    _sessions.add(
      TerminalSession(
        id: uiSessionId,
        profileId: profile.id,
        title: duplicateCount == 0
            ? baseTitle
            : '$baseTitle ${duplicateCount + 1}',
        status: ConnectionStatus.connecting,
        kind: kind,
      ),
    );
    notifyListeners();

    try {
      final connectProfile = await _profileWithResolvedPassword(profile);
      final backendSessionId = await _backend.connect(connectProfile);
      _backendToUiSessionIds[backendSessionId] = uiSessionId;
      notifyListeners();
      return const Right(null);
    } catch (error) {
      final index = _sessions.indexWhere(
        (session) => session.id == uiSessionId,
      );
      if (index != -1) {
        _sessions[index] = _sessions[index].copyWith(
          status: ConnectionStatus.error,
        );
        notifyListeners();
      }
      return Left(
        AppFailure('Failed to connect to ${profile.name}', cause: error),
      );
    }
  }

  Future<void> disconnect(String sessionId) => _backend.disconnect(sessionId);

  @override
  Future<Result<void>> closeSession(String sessionId) async {
    final index = _sessions.indexWhere((session) => session.id == sessionId);
    if (index == -1) {
      return const Left(AppFailure('Session not found'));
    }

    _sessions.removeAt(index);
    final backendSessionId = _backendSessionIdForUiSession(sessionId);
    if (backendSessionId != null) {
      _backendToUiSessionIds.remove(backendSessionId);
    }
    notifyListeners();

    try {
      await _backend.disconnect(backendSessionId ?? sessionId);
      return const Right(null);
    } catch (error) {
      return Left(AppFailure('Failed to disconnect session', cause: error));
    }
  }

  @override
  Future<Result<void>> sendTerminalInput(String sessionId, String data) async {
    try {
      await _backend.sendTerminalInput(
        _backendSessionIdForUiSession(sessionId) ?? sessionId,
        data,
      );
      return const Right(null);
    } catch (error) {
      return Left(AppFailure('Failed to send terminal input', cause: error));
    }
  }

  @override
  Future<Result<void>> resizeTerminal(
    String sessionId,
    int cols,
    int rows,
  ) async {
    try {
      await _backend.resizeTerminal(
        _backendSessionIdForUiSession(sessionId) ?? sessionId,
        cols,
        rows,
      );
      return const Right(null);
    } catch (error) {
      return Left(AppFailure('Failed to resize terminal', cause: error));
    }
  }

  @override
  Future<Result<RemoteSystemSnapshot>> remoteSystemSnapshot(
    String sessionId,
  ) async {
    try {
      final snapshot = await _backend.remoteSystemSnapshot(
        _backendSessionIdForUiSession(sessionId) ?? sessionId,
      );
      return Right(snapshot);
    } catch (error) {
      return Left(AppFailure('Failed to load remote telemetry', cause: error));
    }
  }

  @override
  Future<Result<List<String>>> commandHelpSuggestions(
    String sessionId,
    String input,
  ) async {
    try {
      final suggestions = await _backend.commandHelpSuggestions(
        _backendSessionIdForUiSession(sessionId) ?? sessionId,
        input,
      );
      return Right(suggestions);
    } catch (error) {
      return Left(
        AppFailure('Failed to load command suggestions', cause: error),
      );
    }
  }

  @override
  Future<Result<List<TerminalCompletionCandidate>>> commandCompletions(
    String sessionId,
    String input,
  ) async {
    try {
      final suggestions = await _backend.commandCompletions(
        _backendSessionIdForUiSession(sessionId) ?? sessionId,
        input,
      );
      return Right(suggestions);
    } catch (error) {
      return Left(
        AppFailure('Failed to load command completions', cause: error),
      );
    }
  }

  @override
  Future<Result<TerminalCompleteResponse>> terminalComplete(
    TerminalCompleteRequest request,
  ) async {
    try {
      final sessionId = request.sessionId;
      final backendSessionId = sessionId == null
          ? null
          : _backendSessionIdForUiSession(sessionId) ?? sessionId;
      final response = await _backend.terminalComplete(
        request.copyWith(sessionId: backendSessionId),
      );
      return Right(response);
    } catch (error) {
      return Left(
        AppFailure('Failed to load terminal autocomplete', cause: error),
      );
    }
  }

  @override
  Future<Result<String>> resolveRemoteDirectory(
    String sessionId,
    String path,
  ) async {
    try {
      final resolvedPath = await _backend.resolveRemoteDirectory(
        _backendSessionIdForUiSession(sessionId) ?? sessionId,
        path,
      );
      return Right(resolvedPath);
    } catch (error) {
      return Left(AppFailure('Failed to resolve remote folder', cause: error));
    }
  }

  @override
  Future<Result<List<RemoteFileEntry>>> listRemoteDirectory(
    String sessionId,
    String path,
  ) async {
    try {
      final entries = await _backend.listRemoteDirectory(
        _backendSessionIdForUiSession(sessionId) ?? sessionId,
        path,
      );
      return Right(entries);
    } catch (error) {
      return Left(AppFailure('Failed to load remote folder', cause: error));
    }
  }

  @override
  Future<Result<List<RemoteFileEntry>>> findRemoteEntries(
    String sessionId,
    String basePath,
    String query, {
    int maxResults = 120,
  }) async {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) return const Right([]);
    try {
      final entries = await _findRemoteEntriesBreadthFirst(
        backendSessionId: _backendSessionIdForUiSession(sessionId) ?? sessionId,
        basePath: basePath,
        query: normalizedQuery,
        maxResults: maxResults,
      );
      return Right(entries);
    } catch (error) {
      return Left(AppFailure('Failed to find remote entries', cause: error));
    }
  }

  @override
  Future<Result<String>> readRemoteFile(String sessionId, String path) async {
    try {
      final content = await _backend.readRemoteFile(
        _backendSessionIdForUiSession(sessionId) ?? sessionId,
        path,
      );
      return Right(content);
    } catch (error) {
      return Left(AppFailure('Failed to read remote file', cause: error));
    }
  }

  @override
  Future<Result<List<int>>> readRemoteFileBytes(
    String sessionId,
    String path,
  ) async {
    try {
      final content = await _backend.readRemoteFileBytes(
        _backendSessionIdForUiSession(sessionId) ?? sessionId,
        path,
      );
      return Right(content);
    } catch (error) {
      return Left(AppFailure('Failed to download remote file', cause: error));
    }
  }

  @override
  Future<Result<void>> writeRemoteFile(
    String sessionId,
    String path,
    String content,
  ) async {
    try {
      await _backend.writeRemoteFile(
        _backendSessionIdForUiSession(sessionId) ?? sessionId,
        path,
        content,
      );
      return const Right(null);
    } catch (error) {
      return Left(AppFailure('Failed to save remote file', cause: error));
    }
  }

  @override
  Future<Result<void>> uploadRemoteFile(
    String sessionId,
    String path,
    List<int> data,
  ) async {
    try {
      await _backend.uploadRemoteFile(
        _backendSessionIdForUiSession(sessionId) ?? sessionId,
        path,
        data,
      );
      return const Right(null);
    } catch (error) {
      return Left(AppFailure('Failed to upload file', cause: error));
    }
  }

  @override
  Future<Result<void>> createRemoteDirectory(
    String sessionId,
    String path,
  ) async {
    try {
      await _backend.createRemoteDirectory(
        _backendSessionIdForUiSession(sessionId) ?? sessionId,
        path,
      );
      return const Right(null);
    } catch (error) {
      return Left(AppFailure('Failed to create remote folder', cause: error));
    }
  }

  @override
  Future<Result<void>> createRemoteFile(String sessionId, String path) async {
    try {
      await _backend.createRemoteFile(
        _backendSessionIdForUiSession(sessionId) ?? sessionId,
        path,
      );
      return const Right(null);
    } catch (error) {
      return Left(AppFailure('Failed to create remote file', cause: error));
    }
  }

  @override
  Future<Result<void>> chmodRemotePath(
    String sessionId,
    String path,
    String mode,
  ) async {
    try {
      await _backend.chmodRemotePath(
        _backendSessionIdForUiSession(sessionId) ?? sessionId,
        path,
        mode,
      );
      return const Right(null);
    } catch (error) {
      return Left(AppFailure('Failed to update permissions', cause: error));
    }
  }

  void _handleStatus(ConnectionStatusEvent event) {
    final sessionId =
        _backendToUiSessionIds[event.sessionId] ?? event.sessionId;
    final index = _sessions.indexWhere((session) => session.id == sessionId);
    if (index != -1) {
      _sessions[index] = _sessions[index].copyWith(status: event.status);
      notifyListeners();
    }
  }

  void _handleTerminalOutput(TerminalOutputEvent event) {
    _terminalOutput.add(
      TerminalOutputEvent(
        sessionId: _backendToUiSessionIds[event.sessionId] ?? event.sessionId,
        data: event.data,
      ),
    );
  }

  void _handleError(ConnectionErrorEvent event) {
    final sessionId = event.sessionId;
    _errors.add(
      ConnectionErrorEvent(
        message: event.message,
        sessionId: sessionId == null
            ? null
            : _backendToUiSessionIds[sessionId] ?? sessionId,
      ),
    );
  }

  String? _backendSessionIdForUiSession(String uiSessionId) {
    for (final entry in _backendToUiSessionIds.entries) {
      if (entry.value == uiSessionId) return entry.key;
    }
    return null;
  }

  Future<SshProfile> _profileWithResolvedPassword(SshProfile profile) async {
    if ((profile.privateKeyPath ?? '').trim().isNotEmpty) return profile;
    if ((profile.password ?? '').trim().isNotEmpty) return profile;
    if (!profile.hasPassword) return profile;
    await _waitForSecretWrite(profile.id);
    final password = await _secretStore.readPassword(profile.id);
    if ((password ?? '').isEmpty) {
      throw StateError('Saved password for ${profile.name} is not available');
    }
    return profile.copyWith(password: password);
  }

  void _queueSecretWrite(String profileId, Future<void> write) {
    final trackedWrite = write
        .catchError((Object error) {
          _secretWriteErrors[profileId] = error;
        })
        .whenComplete(() {
          _pendingSecretWrites.remove(profileId);
        });
    _pendingSecretWrites[profileId] = trackedWrite;
  }

  Future<void> _waitForSecretWrite(String profileId) async {
    final pendingWrite = _pendingSecretWrites[profileId];
    if (pendingWrite != null) {
      await pendingWrite;
    }
    final error = _secretWriteErrors.remove(profileId);
    if (error != null) {
      throw StateError('Failed to save profile password: $error');
    }
  }

  static const int _maxRemoteSearchDepth = 18;
  static const int _maxRemoteSearchDirectories = 2200;
  static const Set<String> _remoteSearchSkippedDirectories = {
    '.cache',
    '.cargo',
    '.git',
    '.gradle',
    '.local',
    '.npm',
    '.rustup',
    'Library',
    'cache',
    'dev',
    'node_modules',
    'proc',
    'run',
    'sys',
    'tmp',
  };

  Future<List<RemoteFileEntry>> _findRemoteEntriesBreadthFirst({
    required String backendSessionId,
    required String basePath,
    required String query,
    required int maxResults,
  }) async {
    final results = <RemoteFileEntry>[];
    final visited = <String>{};
    final queue = Queue<_RemoteSearchDirectory>()
      ..add(_RemoteSearchDirectory(basePath, 0));

    while (queue.isNotEmpty &&
        results.length < maxResults &&
        visited.length < _maxRemoteSearchDirectories) {
      final current = queue.removeFirst();
      if (current.depth > _maxRemoteSearchDepth) continue;
      final normalizedPath = current.path.trim().isEmpty
          ? '/'
          : current.path.trim();
      if (!visited.add(normalizedPath)) continue;

      final entries = await _listRemoteDirectoryForFind(
        backendSessionId,
        normalizedPath,
        isBasePath: current.depth == 0,
      );

      final childDirectories = <RemoteFileEntry>[];
      for (final entry in entries) {
        if (results.length >= maxResults) break;
        final haystack = '${entry.name}\n${entry.path}'.toLowerCase();
        if (haystack.contains(query)) {
          results.add(entry);
        }
        if (entry.isDirectory &&
            !_shouldSkipRemoteSearchDirectory(entry, basePath)) {
          childDirectories.add(entry);
        }
      }

      childDirectories.sort(
        (a, b) => _remoteSearchPriority(
          a,
          query,
        ).compareTo(_remoteSearchPriority(b, query)),
      );
      for (final directory in childDirectories) {
        if (visited.length + queue.length >= _maxRemoteSearchDirectories) {
          break;
        }
        queue.add(_RemoteSearchDirectory(directory.path, current.depth + 1));
      }
    }

    return results;
  }

  Future<List<RemoteFileEntry>> _listRemoteDirectoryForFind(
    String backendSessionId,
    String path, {
    required bool isBasePath,
  }) async {
    try {
      return await _backend.listRemoteDirectory(backendSessionId, path);
    } catch (error) {
      if (isBasePath) rethrow;
      return const [];
    }
  }

  int _remoteSearchPriority(RemoteFileEntry entry, String query) {
    final name = entry.name.toLowerCase();
    final path = entry.path.toLowerCase();
    var score = 100;
    if (path.contains(query) || name.contains(query)) score -= 60;
    if (_looksLikeMediaQuery(query) &&
        (name.contains('picture') ||
            name.contains('photo') ||
            name.contains('image') ||
            name.contains('screenshot') ||
            name.contains('download'))) {
      score -= 35;
    }
    if (!name.startsWith('.')) score -= 10;
    return score;
  }

  bool _looksLikeMediaQuery(String query) {
    return query.endsWith('.jpg') ||
        query.endsWith('.jpeg') ||
        query.endsWith('.png') ||
        query.endsWith('.gif') ||
        query.endsWith('.webp') ||
        query.endsWith('.heic') ||
        query.endsWith('.svg');
  }

  bool _shouldSkipRemoteSearchDirectory(
    RemoteFileEntry entry,
    String basePath,
  ) {
    final path = entry.path;
    if (path == '/' || path == basePath) return false;
    if (_remoteSearchSkippedDirectories.contains(entry.name)) return true;
    return path == '/proc' ||
        path.startsWith('/proc/') ||
        path == '/sys' ||
        path.startsWith('/sys/') ||
        path == '/dev' ||
        path.startsWith('/dev/') ||
        path == '/run' ||
        path.startsWith('/run/');
  }

  @override
  void dispose() {
    _statusSub.cancel();
    _outputSub.cancel();
    _errorSub.cancel();
    _terminalOutput.close();
    _errors.close();
    if (_backend case MockConnectionBackend mock) {
      mock.dispose();
    }
    if (_backend case RustBridgeBackend rust) {
      rust.dispose();
    }
    super.dispose();
  }
}

class _RemoteSearchDirectory {
  const _RemoteSearchDirectory(this.path, this.depth);

  final String path;
  final int depth;
}
