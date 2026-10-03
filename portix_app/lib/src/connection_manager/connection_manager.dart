import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/result/either.dart';
import 'connection_backend.dart';
import 'mock_backend.dart';
import 'profile_credentials.dart';
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
    ProfileCredentials? credentials,
  }) : _backend = backend ?? MockConnectionBackend(),
       credentials = credentials ?? ProfileCredentials() {
    _statusSub = _backend.connectionStatusStream.listen(_handleStatus);
    _outputSub = _backend.terminalOutputStream.listen(_handleTerminalOutput);
    _errorSub = _backend.errorEventStream.listen(_handleError);
    _heartbeatTimer = Timer.periodic(
      _heartbeatInterval,
      (_) => _runHeartbeat(),
    );
  }

  final ConnectionBackend _backend;

  /// Saved secrets and jump hosts, shared with SFTP connections.
  final ProfileCredentials credentials;
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
  final _terminalOutput = StreamController<TerminalOutputEvent>.broadcast();
  final _errors = StreamController<ConnectionErrorEvent>.broadcast();
  final _sessionLost = StreamController<String>.broadcast();
  // Open session logs, keyed by UI session id.
  final Map<String, ({String path, IOSink sink})> _recordings = {};

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

  /// Lightweight TCP probe of the session's first hop (the jump host, if
  /// any), used to wait for the network to come back (e.g. after wake from
  /// sleep) before spending a full SSH handshake.
  Future<bool> isSessionHostReachable(String sessionId) async {
    final endpoint = _sessionEndpoints[sessionId];
    return endpoint != null &&
        await _isHostReachable(endpoint.host, endpoint.port);
  }

  Future<bool> _isHostReachable(String host, int port) async {
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
    final baseTitle = profile.name;
    final duplicateCount = _sessions
        .where((session) => session.profileId == profile.id)
        .length;
    _sessions.add(
      TerminalSession(
        id: uiSessionId,
        profileId: profile.id,
        title: duplicateCount == 0
            ? baseTitle
            : '$baseTitle ${duplicateCount + 1}',
        status: ConnectionStatus.connecting,
      ),
    );
    notifyListeners();

    try {
      final connectProfile = await credentials.resolve(profile);
      final entry = connectProfile.entryPoint;
      if (_sessionEndpoints.containsKey(uiSessionId)) {
        _sessionEndpoints[uiSessionId] = (
          host: entry.host.trim(),
          port: entry.port,
        );
      }
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
      final startup = profile.startupCommand;
      if (startup != null) {
        // The shell reads it once it is ready, like typed-ahead input.
        unawaited(
          _backend
              .sendTerminalInput(backendSessionId, '$startup\r')
              .catchError((Object _) {}),
        );
      }
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

  /// Renames a tab; a blank [title] is ignored.
  void renameSession(String sessionId, String title) {
    final index = _sessions.indexWhere((session) => session.id == sessionId);
    if (index == -1 || title.trim().isEmpty) return;
    _sessions[index] = _sessions[index].copyWith(title: title.trim());
    notifyListeners();
  }

  Future<Result<PortForward>> startLocalForward(
    SshProfile profile, {
    required int localPort,
    required String remoteHost,
    required int remotePort,
  }) async {
    try {
      final forward = await _backend.startLocalForward(
        await credentials.resolve(profile),
        localPort,
        remoteHost,
        remotePort,
      );
      return Right(forward);
    } catch (error) {
      return Left(AppFailure('Failed to start port forward', cause: error));
    }
  }

  Future<Result<PortForward>> startSocksProxy(
    SshProfile profile, {
    required int localPort,
  }) async {
    try {
      final proxy = await _backend.startSocksProxy(
        await credentials.resolve(profile),
        localPort,
      );
      return Right(proxy);
    } catch (error) {
      return Left(AppFailure('Failed to start SOCKS proxy', cause: error));
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

  /// Log file the session's output is being appended to, if recording.
  String? recordingPath(String sessionId) => _recordings[sessionId]?.path;

  /// Appends the session's terminal output, without escape sequences, to
  /// [path] until [stopRecording] or the session closes.
  void startRecording(String sessionId, String path) {
    if (_recordings.containsKey(sessionId)) return;
    final file = File(path)..parent.createSync(recursive: true);
    _recordings[sessionId] = (
      path: path,
      sink: file.openWrite(mode: FileMode.append),
    );
    notifyListeners();
  }

  Future<void> stopRecording(String sessionId) async {
    final recording = _recordings.remove(sessionId);
    if (recording == null) return;
    notifyListeners();
    await recording.sink.close();
  }

  Future<Result<void>> closeSession(String sessionId) async {
    final index = _sessions.indexWhere((session) => session.id == sessionId);
    if (index == -1) {
      return const Left(AppFailure('Session not found'));
    }

    unawaited(_recordings.remove(sessionId)?.sink.close());
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

  /// Flutter-side heartbeat: probe every connected terminal session by
  /// attempting a lightweight TCP socket connect to the SSH port. This runs
  /// independently of the Rust keepalive so UI reflects a lost connection
  /// within [_heartbeatInterval] + [_heartbeatTimeout] (~9 s worst-case)
  /// instead of waiting for the Rust keepalive cycle (~17 s).
  Future<void> _runHeartbeat() async {
    final candidates = _sessions
        .where((s) => s.status == ConnectionStatus.connected)
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
    // Forwarded straight to the UI, with backend session ids remapped to the
    // UI session ids the terminal panel subscribes to.
    final sessionId =
        _backendToUiSessionIds[event.sessionId] ?? event.sessionId;
    _recordings[sessionId]?.sink.write(stripTerminalEscapes(event.data));
    _terminalOutput.add(
      TerminalOutputEvent(sessionId: sessionId, data: event.data),
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

  @override
  void dispose() {
    _heartbeatTimer.cancel();
    _statusSub.cancel();
    _outputSub.cancel();
    _errorSub.cancel();
    for (final recording in _recordings.values) {
      unawaited(recording.sink.close());
    }
    _recordings.clear();
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

final _terminalEscape = RegExp(
  // OSC (title etc.), CSI (colors, cursor), charset selection, then any
  // other two-byte escape.
  r'\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)|\x1b\[[0-?]*[ -/]*[@-~]'
  r'|\x1b[()][0-9A-Za-z]|\x1b[@-_=>78]',
);

/// Terminal output as plain text for log files: escape sequences and
/// carriage returns removed.
///
/// ponytail: a sequence split across two output chunks leaks its tail into
/// the log; buffer partial escapes per session if that shows up in practice.
String stripTerminalEscapes(String data) =>
    data.replaceAll(_terminalEscape, '').replaceAll('\r', '');
