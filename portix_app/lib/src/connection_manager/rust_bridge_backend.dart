import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

import '../rust/api/ssh.dart' as rust_api;
import '../rust/domain/profile.dart' as rust_profile;
import '../rust/domain/session.dart' as rust_session;
import '../rust/frb_generated.dart';
import 'connection_backend.dart';
import 'session_models.dart';
import 'ssh_profile.dart';

class RustBridgeBackend implements ConnectionBackend {
  RustBridgeBackend._({
    required Stream<TerminalOutputEvent> outputStream,
    required Stream<ConnectionStatusEvent> statusStream,
    required Stream<ConnectionErrorEvent> errorStream,
  }) : _outputStream = outputStream,
       _statusStream = statusStream,
       _errorStream = errorStream;

  static Future<RustBridgeBackend> create() async {
    const rustLibraryMode = String.fromEnvironment(
      'RUST_LIBRARY_MODE',
      defaultValue: 'dev',
    );

    if (rustLibraryMode == 'production') {
      await RustLib.init(
        externalLibrary: ExternalLibrary.open(
          _productionLibraryPath(),
          debugInfo: 'Portix Rust library',
        ),
      );
    } else {
      await RustLib.init();
    }

    return RustBridgeBackend._(
      outputStream: rust_api
          .terminalOutputStream()
          .map(_terminalOutputFromJson)
          .asBroadcastStream(),
      statusStream: rust_api
          .connectionStatusStream()
          .map(_connectionStatusFromJson)
          .asBroadcastStream(),
      errorStream: rust_api
          .errorEventStream()
          .map(_errorMessageFromJson)
          .asBroadcastStream(),
    );
  }

  final Stream<TerminalOutputEvent> _outputStream;
  final Stream<ConnectionStatusEvent> _statusStream;
  final Stream<ConnectionErrorEvent> _errorStream;

  @override
  Stream<TerminalOutputEvent> get terminalOutputStream => _outputStream;

  @override
  Stream<ConnectionStatusEvent> get connectionStatusStream => _statusStream;

  @override
  Stream<ConnectionErrorEvent> get errorEventStream => _errorStream;

  @override
  Future<String> connect(SshProfile profile) async {
    final session = await rust_api.connect(
      profile: toRustProfile(profile),
      cols: 80,
      rows: 24,
    );
    return session.id;
  }

  @override
  Future<void> disconnect(String sessionId) {
    return rust_api.disconnect(sessionId: sessionId);
  }

  @override
  Future<void> resizeTerminal(String sessionId, int cols, int rows) {
    return rust_api.resizeTerminal(
      sessionId: sessionId,
      cols: cols,
      rows: rows,
    );
  }

  @override
  Future<void> sendTerminalInput(String sessionId, String data) {
    return rust_api.sendTerminalInput(
      sessionId: sessionId,
      data: utf8.encode(data),
    );
  }

  @override
  Future<RemoteSystemSnapshot> remoteSystemSnapshot(String sessionId) async {
    final snapshot = await rust_api.remoteSystemSnapshot(sessionId: sessionId);
    return snapshot.toAppSnapshot();
  }

  void dispose() {
    RustLib.dispose();
  }

  @override
  Future<HostKeyInfo?> pendingHostKey(String host, int port) async {
    final info = await rust_api.pendingHostKey(host: host, port: port);
    if (info == null) return null;
    return HostKeyInfo(
      algorithm: info.algorithm,
      fingerprint: info.fingerprint,
      changedLine: info.changedLine,
    );
  }

  @override
  Future<void> trustHostKey(String host, int port, String fingerprint) =>
      rust_api.trustHostKey(host: host, port: port, fingerprint: fingerprint);

  @override
  Future<PortForward> startLocalForward(
    SshProfile profile,
    int localPort,
    String remoteHost,
    int remotePort,
  ) async => _toPortForward(
    await rust_api.startLocalForward(
      profile: toRustProfile(profile),
      localPort: localPort,
      remoteHost: remoteHost,
      remotePort: remotePort,
    ),
  );

  @override
  Future<PortForward> startSocksProxy(
    SshProfile profile,
    int localPort,
  ) async => _toPortForward(
    await rust_api.startSocksProxy(
      profile: toRustProfile(profile),
      localPort: localPort,
    ),
  );

  @override
  Future<void> stopLocalForward(String id) => rust_api.stopLocalForward(id: id);

  @override
  Future<List<PortForward>> listLocalForwards() async => [
    for (final forward in await rust_api.listLocalForwards())
      _toPortForward(forward),
  ];

  PortForward _toPortForward(rust_api.ForwardInfo forward) => PortForward(
    id: forward.id,
    profileId: forward.profileId,
    localPort: forward.localPort,
    remoteHost: forward.remoteHost,
    remotePort: forward.remotePort,
    socks: forward.socks,
  );
}

/// The profile as the Rust side takes it (terminal and SFTP alike).
rust_profile.SshProfile toRustProfile(SshProfile profile) {
  final jumpHost = profile.jumpHost;
  return rust_profile.SshProfile(
    id: profile.id,
    name: profile.name,
    host: profile.host,
    port: profile.port,
    username: profile.username,
    password: _blankToNull(profile.password),
    privateKeyPath: _blankToNull(profile.privateKeyPath),
    keyPassphrase: _blankToNull(profile.keyPassphrase),
    jumpHost: jumpHost == null ? null : toRustProfile(jumpHost),
  );
}

TerminalOutputEvent _terminalOutputFromJson(String source) {
  final json = jsonDecode(source) as Map<String, Object?>;
  return TerminalOutputEvent(
    sessionId: json['session_id']! as String,
    data: utf8.decode((json['data']! as List<dynamic>).cast<int>()),
  );
}

ConnectionStatusEvent _connectionStatusFromJson(String source) {
  final json = jsonDecode(source) as Map<String, Object?>;
  return ConnectionStatusEvent(
    sessionId: json['session_id']! as String,
    status: _statusFromRust(json['status']! as String),
    message: json['message'] as String?,
  );
}

ConnectionErrorEvent _errorMessageFromJson(String source) {
  final json = jsonDecode(source) as Map<String, Object?>;
  final message = json['message'] as String? ?? 'Unknown Rust backend error';
  final sessionId = json['session_id'] as String?;
  return ConnectionErrorEvent(message: message, sessionId: sessionId);
}

ConnectionStatus _statusFromRust(String status) {
  return switch (status) {
    'Disconnected' || 'disconnected' => ConnectionStatus.disconnected,
    'Connecting' || 'connecting' => ConnectionStatus.connecting,
    'Connected' || 'connected' => ConnectionStatus.connected,
    'Error' || 'error' => ConnectionStatus.error,
    _ => ConnectionStatus.error,
  };
}

String? _blankToNull(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

extension on rust_session.RemoteSystemSnapshot {
  RemoteSystemSnapshot toAppSnapshot() {
    return RemoteSystemSnapshot(
      os: os,
      hostname: hostname,
      uptime: uptime,
      memory: memory,
      disk: disk,
      memoryUsedBytes: memoryUsedBytes.toInt(),
      memoryFreeBytes: memoryFreeBytes.toInt(),
      memoryTotalBytes: memoryTotalBytes.toInt(),
      diskUsedBytes: diskUsedBytes.toInt(),
      diskFreeBytes: diskFreeBytes.toInt(),
      diskTotalBytes: diskTotalBytes.toInt(),
    );
  }
}

String _productionLibraryPath() {
  final executableDir = File(Platform.resolvedExecutable).parent.path;

  if (Platform.isMacOS) {
    return '$executableDir/libportix_serv.dylib';
  }

  if (Platform.isWindows) {
    return '$executableDir\\portix_serv.dll';
  }

  if (Platform.isLinux) {
    return '$executableDir/libportix_serv.so';
  }

  throw UnsupportedError('Unsupported platform');
}
