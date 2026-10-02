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
  // Host/port of each UI session, so the heartbeat knows what to probe.
  final Map<String, ({String host, int port})> _sessionEndpoints = {};
  // Key profiles whose key turned out to be encrypted; only these read the
  // passphrase from the keychain, so unencrypted keys never touch it.
  final Set<String> _keyPassphraseProfiles = {};
  final _terminalOutput = StreamController<TerminalOutputEvent>.broadcast();
  final _errors = StreamController<ConnectionErrorEvent>.broadcast();
  final _sessionLost = StreamController<String>.broadcast();

  final List<TerminalSession> _sessions = [];

  List<TerminalSession> get sessions => List.unmodifiable(_sessions);

  Stream<TerminalOutputEvent> get terminalOutputStream =>
      _terminalOutput.stream;

  Stream<ConnectionErrorEvent> get errorEventStream => _errors.stream;

  /// UI session ids whose established connection dropped unexpectedly
  /// (heartbeat failure or backend error/disconnect while connected).
  /// User-initiated closes never fire this — [closeSession] removes the
  /// session before the backend reports the disconnect.
  Stream<String> get sessionLostStream => _sessionLost.stream;

  /// Lightweight TCP probe, used to wait for the network to come back
  /// (e.g. after wake from sleep) before spending a full SSH handshake.
  Future<bool> isHostReachable(String host, int port) async {
    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: _heartbeatTimeout,
      );
      await socket.close();
      return true;
    } catch (_) {
      return false;
    }
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
    _sessionEndpoints[uiSessionId] = (
      host: profile.host.trim(),
      port: profile.port,
    );
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

  Future<Result<PortForward>> startLocalForward(
    SshProfile profile, {
    required int localPort,
    required String remoteHost,
    required int remotePort,
  }) async {
    try {
      final forward = await _backend.startLocalForward(
        await _profileWithResolvedPassword(profile),
        localPort,
        remoteHost,
        remotePort,
      );
      return Right(forward);
    } catch (error) {
      return Left(AppFailure('Failed to start port forward', cause: error));
    }
  }

  Future<void> stopLocalForward(String id) => _backend.stopLocalForward(id);

  Future<List<PortForward>> listLocalForwards() =>
      _backend.listLocalForwards().catchError((Object _) => <PortForward>[]);

  /// The host key refused during the last connect to [profile], if any.
  /// Lookup failures read as "no pending key" so the caller falls back to
  /// its generic connection error.
  Future<HostKeyInfo?> pendingHostKey(SshProfile profile) => _backend
      .pendingHostKey(profile.host, profile.port)
      .then<HostKeyInfo?>((info) => info, onError: (Object _) => null);

  Future<Result<void>> trustHostKey(
    SshProfile profile,
    String fingerprint,
  ) async {
    try {
      await _backend.trustHostKey(profile.host, profile.port, fingerprint);
      return const Right(null);
    } catch (error) {
      return Left(AppFailure('Failed to trust host key', cause: error));
    }
  }

  /// Marks [profileId]'s key as encrypted, so connects send the passphrase
  /// saved in the keychain (the slot a password profile uses).
  void useSavedKeyPassphrase(String profileId) =>
      _keyPassphraseProfiles.add(profileId);

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

  /// Reads the saved password for the given profile from secure storage.
  /// Used when duplicating a connected session to a new window so the
  /// child window can reconnect without re-prompting for a password.
  Future<String?> readProfilePassword(String profileId) async {
    return _secretStore.readPassword(profileId);
  }

  Future<Result<void>> closeSession(String sessionId) async {
    final index = _sessions.indexWhere((session) => session.id == sessionId);
    if (index == -1) {
      return const Left(AppFailure('Session not found'));
    }

    _sessions.removeAt(index);
    _sessionEndpoints.remove(sessionId);
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

  Future<Result<void>> sendTerminalInput(String sessionId, String data) =>
      _call(
        sessionId,
        'Failed to send terminal input',
        (id) => _backend.sendTerminalInput(id, data),
      );

  Future<Result<void>> executeRemoteCommand(
    String sessionId,
    String command, {
    String action = 'remote command',
    Duration timeout = const Duration(seconds: 20),
  }) async {
    final backendSessionId = _backendId(sessionId);

    Result<void> result;
    try {
      // Run the command on the session's DEDICATED exec channel (a separate SSH
      // channel, not the interactive shell). This used to send the command
      // through `sendTerminalInput` (the interactive shell), which:
      //   - recorded SFTP file-management commands (rename/move/delete/duplicate)
      //     in the remote shell's shared history file (HISTFILE), so they showed
      //     up when pressing ⬆ in the SSH terminal ("masuk ke history"), and
      //   - echoed the command plus a `__PORTIX_CMD_..._EXIT` marker line into
      //     the visible terminal output.
      // The exec channel opens a fresh SSH `exec` session that never touches the
      // user's interactive shell, so neither the command nor any marker reaches
      // the shell history or the terminal. A non-zero exit status is surfaced
      // directly as an exception by the Rust backend (see `run_exec`).
      await _backend
          .execRemoteCommand(backendSessionId, command)
          .timeout(
            timeout,
            onTimeout: () => throw TimeoutException(
              'Timed out while running $action',
              timeout,
            ),
          );
      result = const Right(null);
    } on TimeoutException catch (_) {
      result = Left(AppFailure('Timed out while running $action'));
    } catch (error) {
      result = Left(AppFailure('Failed to run $action', cause: error));
    }

    // Forward a concise command-result line (green ✓ / red ✗) to the SSH
    // terminal panel so the user gets feedback that the SFTP/file-manager
    // operation ran — WITHOUT echoing the underlying command or any marker
    // into the remote shell history. SFTP sessions have no terminal panel, so
    // the summary is intentionally only shown for SSH terminal sessions.
    _forwardRemoteCommandResult(sessionId, action, result);
    return result;
  }

  /// Forwards a concise command-result line to the terminal output stream so
  /// the user can see in the SSH terminal whether a remote file-management
  /// command (rename/move/delete/duplicate) succeeded or failed.
  ///
  /// Only SSH terminal sessions have a terminal panel to display this; SFTP
  /// sessions do not, so the summary is skipped for them.
  void _forwardRemoteCommandResult(
    String uiSessionId,
    String action,
    Result<void> result,
  ) {
    // Only SSH terminal sessions have a terminal panel to display the result.
    final index = _sessions.indexWhere((s) => s.id == uiSessionId);
    if (index == -1 || _sessions[index].kind != SessionKind.ssh) {
      return;
    }

    final status = result.isRight ? '\x1b[32m✓\x1b[0m' : '\x1b[31m✗\x1b[0m';
    _terminalOutput.add(
      TerminalOutputEvent(
        sessionId: uiSessionId,
        data: '\r\n\x1b[36m[portix] $action\x1b[0m $status\r\n',
      ),
    );
  }

  Future<Result<void>> resizeTerminal(String sessionId, int cols, int rows) =>
      _call(
        sessionId,
        'Failed to resize terminal',
        (id) => _backend.resizeTerminal(id, cols, rows),
      );

  Future<Result<RemoteSystemSnapshot>> remoteSystemSnapshot(String sessionId) =>
      _call(
        sessionId,
        'Failed to load remote telemetry',
        _backend.remoteSystemSnapshot,
      );

  Future<Result<String>> resolveRemoteDirectory(
    String sessionId,
    String path,
  ) => _call(
    sessionId,
    'Failed to resolve remote folder',
    (id) => _backend.resolveRemoteDirectory(id, path),
  );

  Future<Result<List<RemoteFileEntry>>> listRemoteDirectory(
    String sessionId,
    String path,
  ) => _call(
    sessionId,
    'Failed to load remote folder',
    (id) => _backend.listRemoteDirectory(id, path),
  );

  Future<Result<List<RemoteFileEntry>>> findRemoteEntries(
    String sessionId,
    String basePath,
    String query, {
    int maxResults = 120,
  }) async {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) return const Right([]);
    return _call(
      sessionId,
      'Failed to find remote entries',
      (id) => _findRemoteEntriesBreadthFirst(
        backendSessionId: id,
        basePath: basePath,
        query: normalizedQuery,
        maxResults: maxResults,
      ),
    );
  }

  Future<Result<String>> readRemoteFile(String sessionId, String path) => _call(
    sessionId,
    'Failed to read remote file',
    (id) => _backend.readRemoteFile(id, path),
  );

  Future<Result<List<int>>> readRemoteFileBytes(
    String sessionId,
    String path,
  ) => _call(
    sessionId,
    'Failed to download remote file',
    (id) => _backend.readRemoteFileBytes(id, path),
  );

  Future<Result<void>> writeRemoteFile(
    String sessionId,
    String path,
    String content,
  ) => _call(
    sessionId,
    'Failed to save remote file',
    (id) => _backend.writeRemoteFile(id, path, content),
  );

  Future<Result<void>> uploadRemoteFile(
    String sessionId,
    String path,
    List<int> data,
  ) => _call(
    sessionId,
    'Failed to upload file',
    (id) => _backend.uploadRemoteFile(id, path, data),
  );

  Future<Result<void>> createRemoteDirectory(String sessionId, String path) =>
      _call(
        sessionId,
        'Failed to create remote folder',
        (id) => _backend.createRemoteDirectory(id, path),
      );

  Future<Result<void>> createRemoteFile(String sessionId, String path) => _call(
    sessionId,
    'Failed to create remote file',
    (id) => _backend.createRemoteFile(id, path),
  );

  Future<Result<void>> chmodRemotePath(
    String sessionId,
    String path,
    String mode,
  ) => _call(
    sessionId,
    'Failed to update permissions',
    (id) => _backend.chmodRemotePath(id, path, mode),
  );

  /// Runs [operation] against the backend session behind UI [sessionId],
  /// turning any thrown error into a [Left] carrying [failureMessage].
  Future<Result<T>> _call<T>(
    String sessionId,
    String failureMessage,
    Future<T> Function(String backendSessionId) operation,
  ) async {
    try {
      return Right(await operation(_backendId(sessionId)));
    } catch (error) {
      return Left(AppFailure(failureMessage, cause: error));
    }
  }

  String _backendId(String uiSessionId) =>
      _backendSessionIdForUiSession(uiSessionId) ?? uiSessionId;

  /// Flutter-side heartbeat: probe every connected *SSH terminal* session by
  /// attempting a lightweight TCP socket connect to the SSH port. This runs
  /// independently of the Rust keepalive so UI reflects a lost connection
  /// within [_heartbeatInterval] + [_heartbeatTimeout] (~9 s worst-case)
  /// instead of waiting for the Rust keepalive cycle (~17 s).
  ///
  /// SFTP sessions are intentionally EXCLUDED from this TCP probe. SFTP
  /// sessions ride on the same Rust-managed SSH connection whose keepalive is
  /// already driven server-side (see `ssh_client.rs`). Spinning up a *new*
  /// TCP socket to host:port gives false "connection lost" positives whenever
  /// the remote blocks new TCP connections, enforces per-host connection
  /// limits, or briefly rejects new sockets — even though the existing SSH/SFTP
  /// channel is perfectly alive. SFTP disconnects are detected instead through
  /// the Rust keepalive and by consecutive SFTP-operation failures
  /// (see `SftpWorkspaceController._recordRemoteFailure`).
  Future<void> _runHeartbeat() async {
    // Collect all currently-connected SSH terminal sessions with a known profile.
    // SFTP sessions are skipped — see the doc above.
    final candidates = _sessions
        .where(
          (s) =>
              s.status == ConnectionStatus.connected &&
              s.kind == SessionKind.ssh,
        )
        .toList(growable: false);

    for (final session in candidates) {
      if (_heartbeatInFlight.contains(session.id)) continue;

      final endpoint = _sessionEndpoints[session.id];
      if (endpoint == null || endpoint.host.isEmpty) continue;
      final (:host, :port) = endpoint;

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
    _sessionLost.add(uiSessionId);

    // Tell Rust to clean up the session too (best-effort).
    final backendId = _backendId(uiSessionId);
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
      if (previous.status == ConnectionStatus.connected) {
        _sessionLost.add(sessionId);
      }
    }
  }

  void _handleTerminalOutput(TerminalOutputEvent event) {
    // Remote file-management commands now run on a dedicated exec channel
    // (see `executeRemoteCommand`), so this listener never needs to intercept
    // terminal output to detect a command marker. All SSH terminal output is
    // forwarded straight to the UI, with backend session IDs remapped to the
    // UI session IDs the terminal panel subscribes to.
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
    if ((profile.privateKeyPath ?? '').trim().isNotEmpty) {
      if (!_keyPassphraseProfiles.contains(profile.id)) return profile;
      final passphrase = await _secretStore
          .readPassword(profile.id)
          .catchError((Object _) => null);
      return (passphrase ?? '').isEmpty
          ? profile
          : profile.copyWith(keyPassphrase: passphrase);
    }
    if ((profile.password ?? '').trim().isNotEmpty) return profile;
    if (!profile.hasPassword) return profile;
    final password = await _secretStore.readPassword(profile.id);
    if ((password ?? '').isEmpty) {
      throw PasswordUnavailableException(profile.name, profile.id);
    }
    return profile.copyWith(password: password);
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
    _sessionLost.close();
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

class PasswordUnavailableException implements Exception {
  const PasswordUnavailableException(this.profileName, this.profileId);

  final String profileName;
  final String profileId;

  String toString() =>
      'Saved password for "$profileName" is not available on this device. '
      'Please re-enter the password.';
}
