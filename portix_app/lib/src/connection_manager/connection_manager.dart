import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/result/either.dart';
import 'connection_backend.dart';
import 'mock_backend.dart';
import 'profile_secret_store.dart';
import 'rust_bridge_backend.dart';
import 'session_models.dart';
import 'ssh_profile.dart';

/// How often the Flutter-side heartbeat probes each connected session.
/// This runs independently of the Rust keepalive so disconnect is detected
/// as soon as either side notices — whichever fires first.
const Duration _heartbeatInterval = Duration(seconds: 5);

/// Timeout for a single heartbeat probe. Must be shorter than
/// [_heartbeatInterval] so probes do not stack.
const Duration _heartbeatTimeout = Duration(seconds: 4);

class ConnectionManager extends ChangeNotifier {
  ConnectionManager({
    ConnectionBackend? backend,
    ProfileSecretStore? secretStore,
  }) : _backend = backend ?? MockConnectionBackend(),
       _secretStore = secretStore ?? const ProfileSecretStore() {
    _statusSub = _backend.connectionStatusStream.listen(_handleStatus);
    _outputSub = _backend.terminalOutputStream.listen(_handleTerminalOutput);
    _errorSub = _backend.errorEventStream.listen(_handleError);
    _heartbeatTimer = Timer.periodic(
      _heartbeatInterval,
      (_) => _runHeartbeat(),
    );
  }

  final ConnectionBackend _backend;
  final ProfileSecretStore _secretStore;
  final _uuid = const Uuid();
  late final StreamSubscription<ConnectionStatusEvent> _statusSub;
  late final StreamSubscription<TerminalOutputEvent> _outputSub;
  late final StreamSubscription<ConnectionErrorEvent> _errorSub;
  late final Timer _heartbeatTimer;
  // Sessions currently being probed — avoid parallel probes for the same session.
  final Set<String> _heartbeatInFlight = {};
  final Map<String, String> _backendToUiSessionIds = {};
  final Map<String, Future<void>> _pendingSecretWrites = {};
  final Map<String, Object> _secretWriteErrors = {};
  final Map<String, _RemoteCommandCapture> _remoteCommandCaptures = {};
  final _terminalOutput = StreamController<TerminalOutputEvent>.broadcast();
  final _errors = StreamController<ConnectionErrorEvent>.broadcast();

  final List<SshProfile> _profiles = [];

  final List<TerminalSession> _sessions = [];

  List<SshProfile> get profiles => List.unmodifiable(_profiles);

  List<TerminalSession> get sessions => List.unmodifiable(_sessions);

  Stream<TerminalOutputEvent> get terminalOutputStream =>
      _terminalOutput.stream;

  Stream<ConnectionErrorEvent> get errorEventStream => _errors.stream;

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

  SshProfile newProfile() {
    return SshProfile(
      id: _uuid.v4(),
      name: 'New server',
      host: '',
      port: 22,
      username: '',
    );
  }

  Future<Result<void>> connect(SshProfile profile) async {
    return _connect(profile, kind: SessionKind.ssh);
  }

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
      // Rust enforces CONNECT_TIMEOUT (15s) + AUTH_TIMEOUT (15s) = ~30s.
      // Add a Flutter-side safety net slightly above that so the UI never
      // hangs indefinitely when the remote host is unreachable.
      final backendSessionId = await _backend
          .connect(connectProfile)
          .timeout(
            const Duration(seconds: 40),
            onTimeout: () => throw TimeoutException(
              'Connection timed out. The remote host is not responding.',
              const Duration(seconds: 40),
            ),
          );
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

  /// Save a password to secure storage so future connections can use it.
  Future<void> saveProfilePassword(String profileId, String password) async {
    await _secretStore.savePassword(profileId, password);
  }

  /// Returns true when a usable password for the given profile is already
  /// stored in the local secure keychain / secret store.
  Future<bool> hasSavedPassword(String profileId) async {
    final password = await _secretStore.readPassword(profileId);
    return (password ?? '').trim().isNotEmpty;
  }

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

  Future<Result<void>> executeRemoteCommand(
    String sessionId,
    String command, {
    String action = 'remote command',
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final backendSessionId =
        _backendSessionIdForUiSession(sessionId) ?? sessionId;
    final token = _uuid.v4().replaceAll('-', '');
    final marker = '__PORTIX_CMD_${token}_EXIT:';
    final capture = _RemoteCommandCapture(marker);
    _remoteCommandCaptures[backendSessionId] = capture;
    Timer? timer;

    try {
      timer = Timer(timeout, () {
        if (!capture.completer.isCompleted) {
          capture.completer.complete(
            Left(AppFailure('Timed out while running $action')),
          );
        }
        _remoteCommandCaptures.remove(backendSessionId);
      });

      // Prefix with space to avoid shell history (HISTCONTROL=ignorespace).
      final wrappedCommand =
          ' { $command; }; __portix_status=\$?; printf "\\n$marker%s__\\n" "\$__portix_status"\n';
      await _backend.sendTerminalInput(backendSessionId, wrappedCommand);
      return await capture.completer.future;
    } catch (error) {
      _remoteCommandCaptures.remove(backendSessionId);
      return Left(AppFailure('Failed to run $action', cause: error));
    } finally {
      timer?.cancel();
      _remoteCommandCaptures.remove(backendSessionId);
    }
  }

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

  /// Flutter-side heartbeat: probe every connected session by attempting a
  /// lightweight TCP socket connect to the SSH port. This runs independently
  /// of the Rust keepalive so UI reflects a lost connection within
  /// [_heartbeatInterval] + [_heartbeatTimeout] (~9 s worst-case) instead of
  /// waiting for the Rust keepalive cycle (~17 s).
  Future<void> _runHeartbeat() async {
    // Collect all currently-connected sessions with a known profile.
    final candidates = _sessions
        .where((s) => s.status == ConnectionStatus.connected)
        .toList(growable: false);

    for (final session in candidates) {
      if (_heartbeatInFlight.contains(session.id)) continue;

      // Find the SshProfile for this session so we know host + port.
      final profile = _profiles
          .where((p) => p.id == session.profileId)
          .firstOrNull;
      if (profile == null) continue;
      final host = profile.host.trim();
      final port = profile.port;
      if (host.isEmpty) continue;

      _heartbeatInFlight.add(session.id);
      unawaited(
        _probeSession(
          session.id,
          host,
          port,
        ).whenComplete(() => _heartbeatInFlight.remove(session.id)),
      );
    }
  }

  Future<void> _probeSession(String uiSessionId, String host, int port) async {
    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: _heartbeatTimeout,
      );
      // Connection succeeded — remote is still reachable.
      await socket.close();
    } on SocketException {
      // TCP refused or timed out — remote is gone.
      _markSessionDead(uiSessionId, 'Connection lost. Host is unreachable.');
    } on TimeoutException {
      _markSessionDead(uiSessionId, 'Connection timed out.');
    } catch (_) {
      // Any other OS-level error also counts as unreachable.
      _markSessionDead(uiSessionId, 'Connection lost.');
    }
  }

  void _markSessionDead(String uiSessionId, String message) {
    final index = _sessions.indexWhere((s) => s.id == uiSessionId);
    if (index == -1) return;
    final session = _sessions[index];
    // Only act if still considered connected — avoid double-firing.
    if (session.status != ConnectionStatus.connected) return;

    _sessions[index] = session.copyWith(status: ConnectionStatus.error);
    notifyListeners();
    _errors.add(ConnectionErrorEvent(message: message, sessionId: uiSessionId));

    // Tell Rust to clean up the session too (best-effort).
    final backendId = _backendSessionIdForUiSession(uiSessionId) ?? uiSessionId;
    unawaited(_backend.disconnect(backendId).catchError((_) {}));
  }

  void _handleStatus(ConnectionStatusEvent event) {
    final sessionId =
        _backendToUiSessionIds[event.sessionId] ?? event.sessionId;
    final index = _sessions.indexWhere((session) => session.id == sessionId);
    if (index == -1) return;

    final previous = _sessions[index];
    _sessions[index] = previous.copyWith(status: event.status);
    notifyListeners();

    // When a session transitions to error or disconnected unexpectedly,
    // surface a message to the UI so the terminal panel can show a reconnect prompt.
    final wasActive =
        previous.status == ConnectionStatus.connected ||
        previous.status == ConnectionStatus.connecting;
    final isUnexpectedDrop =
        event.status == ConnectionStatus.error ||
        event.status == ConnectionStatus.disconnected;
    if (wasActive && isUnexpectedDrop) {
      final message = event.message?.isNotEmpty == true
          ? event.message!
          : 'Connection lost. Check your network or VPN, then reconnect.';
      _errors.add(ConnectionErrorEvent(message: message, sessionId: sessionId));
    }
  }

  void _handleTerminalOutput(TerminalOutputEvent event) {
    final capture = _remoteCommandCaptures[event.sessionId];
    if (capture != null) {
      capture.append(event.data);
      if (capture.isComplete) {
        if (!capture.completer.isCompleted) {
          capture.completer.complete(capture.result);
        }
        _remoteCommandCaptures.remove(event.sessionId);
      }
      return;
    }
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
      throw PasswordUnavailableException(profile.name, profile.id);
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

  static const int _maxRemoteSearchDepth = 12;
  static const int _maxRemoteSearchDirectories = 600;
  static const Set<String> _remoteSearchSkippedDirectories = {
    '.cache',
    '.cargo',
    '.git',
    '.gradle',
    '.local',
    '.npm',
    '.rustup',
    '.venv',
    '.tox',
    '.m2',
    '.pub-cache',
    '__pycache__',
    'Library',
    'cache',
    'dev',
    'node_modules',
    'proc',
    'run',
    'sys',
    'tmp',
    'vendor',
    'target',
    'build',
    'dist',
    '.next',
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

    // Process directories in parallel batches for faster searching.
    const batchSize = 6;

    while (queue.isNotEmpty &&
        results.length < maxResults &&
        visited.length < _maxRemoteSearchDirectories) {
      // Collect a batch of directories to process in parallel.
      final batch = <_RemoteSearchDirectory>[];
      while (batch.length < batchSize && queue.isNotEmpty) {
        final current = queue.removeFirst();
        if (current.depth > _maxRemoteSearchDepth) continue;
        final normalizedPath = current.path.trim().isEmpty
            ? '/'
            : current.path.trim();
        if (!visited.add(normalizedPath)) continue;
        batch.add(_RemoteSearchDirectory(normalizedPath, current.depth));
      }
      if (batch.isEmpty) continue;

      // List all directories in the batch concurrently.
      final futures = batch.map(
        (dir) => _listRemoteDirectoryForFind(
          backendSessionId,
          dir.path,
          isBasePath: dir.depth == 0,
        ).then((entries) => (dir, entries)),
      );

      final batchResults = await Future.wait(futures);

      for (final (dir, entries) in batchResults) {
        if (results.length >= maxResults) break;

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
          queue.add(_RemoteSearchDirectory(directory.path, dir.depth + 1));
        }
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
    _heartbeatTimer.cancel();
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

class _RemoteCommandCapture {
  _RemoteCommandCapture(this.marker);

  final String marker;
  final Completer<Result<void>> completer = Completer<Result<void>>();
  final StringBuffer _buffer = StringBuffer();
  bool _complete = false;
  Result<void> _result = const Right(null);

  bool get isComplete => _complete;
  Result<void> get result => _result;

  void append(String data) {
    if (_complete) return;
    _buffer.write(data);
    final output = _buffer.toString();
    // Strip ANSI escape sequences before matching the marker.
    final clean = output.replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '');
    final match = RegExp('${RegExp.escape(marker)}(\\d+)__').firstMatch(clean);
    if (match == null) return;
    final status = int.tryParse(match.group(1)!);
    _complete = true;
    if (status == 0) {
      _result = const Right(null);
      return;
    }
    final markerIndex = match.start;
    final details = clean.substring(0, markerIndex).trim();
    _result = Left(
      AppFailure(
        details.isEmpty
            ? 'Remote command failed with exit code ${status ?? 'unknown'}'
            : details,
      ),
    );
  }
}

class PasswordUnavailableException implements Exception {
  const PasswordUnavailableException(this.profileName, this.profileId);

  final String profileName;
  final String profileId;

  String toString() =>
      'Saved password for "$profileName" is not available on this device. '
      'Please re-enter the password.';
}
