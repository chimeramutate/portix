import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';

import '../rust/api.dart' as rust_api;
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
      final devLibraryPath = _devLibraryPath();
      if (devLibraryPath != null) {
        await RustLib.init(
          externalLibrary: ExternalLibrary.open(
            devLibraryPath,
            debugInfo: 'Portix Rust dev library',
          ),
        );
      } else {
        await RustLib.init();
      }
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
      profile: profile.toRustProfile(),
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

  @override
  Future<List<String>> commandHelpSuggestions(String sessionId, String input) {
    return rust_api.commandHelpSuggestions(sessionId: sessionId, input: input);
  }

  @override
  Future<List<TerminalCompletionCandidate>> commandCompletions(
    String sessionId,
    String input,
  ) async {
    final suggestions = await commandHelpSuggestions(sessionId, input);
    return suggestions
        .map(TerminalCompletionCandidate.fromWire)
        .where((candidate) => candidate.replacement.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<TerminalCompleteResponse> terminalComplete(
    TerminalCompleteRequest request,
  ) async {
    final response = await rust_api.terminalComplete(
      reqJson: jsonEncode(request.toJson()),
    );
    final decoded = jsonDecode(response);
    if (decoded is! Map) {
      return const TerminalCompleteResponse();
    }
    return TerminalCompleteResponse.fromJson(decoded.cast<String, Object?>());
  }

  @override
  Future<String> resolveRemoteDirectory(String sessionId, String path) {
    return rust_api.resolveRemoteDirectory(sessionId: sessionId, path: path);
  }

  @override
  Future<List<RemoteFileEntry>> listRemoteDirectory(
    String sessionId,
    String path,
  ) async {
    final entries = await rust_api.listRemoteDirectory(
      sessionId: sessionId,
      path: path,
    );
    return entries.map((entry) => entry.toAppEntry()).toList();
  }

  @override
  Future<String> readRemoteFile(String sessionId, String path) {
    return rust_api.readRemoteFile(sessionId: sessionId, path: path);
  }

  @override
  Future<List<int>> readRemoteFileBytes(String sessionId, String path) {
    return rust_api.readRemoteFileBytes(sessionId: sessionId, path: path);
  }

  @override
  Future<void> writeRemoteFile(String sessionId, String path, String content) {
    return rust_api.writeRemoteFile(
      sessionId: sessionId,
      path: path,
      content: content,
    );
  }

  @override
  Future<void> uploadRemoteFile(String sessionId, String path, List<int> data) {
    return rust_api.uploadRemoteFile(
      sessionId: sessionId,
      path: path,
      data: data,
    );
  }

  @override
  Future<void> createRemoteDirectory(String sessionId, String path) {
    return rust_api.createRemoteDirectory(sessionId: sessionId, path: path);
  }

  @override
  Future<void> createRemoteFile(String sessionId, String path) {
    return rust_api.createRemoteFile(sessionId: sessionId, path: path);
  }

  @override
  Future<void> chmodRemotePath(String sessionId, String path, String mode) {
    return rust_api.chmodRemotePath(
      sessionId: sessionId,
      path: path,
      mode: mode,
    );
  }

  void dispose() {
    RustLib.dispose();
  }
}

extension on SshProfile {
  rust_profile.SshProfile toRustProfile() {
    return rust_profile.SshProfile(
      id: id,
      name: name,
      host: host,
      port: port,
      username: username,
      password: _blankToNull(password),
      privateKeyPath: _blankToNull(privateKeyPath),
    );
  }
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

extension on rust_session.RemoteFileEntry {
  RemoteFileEntry toAppEntry() {
    return RemoteFileEntry(
      name: name,
      path: path,
      isDirectory: isDirectory,
      sizeBytes: sizeBytes.toInt(),
      modifiedUnixSeconds: modifiedUnixSeconds.toInt(),
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

String? _devLibraryPath() {
  final libraryName = Platform.isMacOS
      ? 'libportix_serv.dylib'
      : Platform.isWindows
      ? 'portix_serv.dll'
      : Platform.isLinux
      ? 'libportix_serv.so'
      : null;
  if (libraryName == null) return null;

  final candidates = <String>[
    '${Directory.current.path}/../portix-serv/target/release/$libraryName',
    '${Directory.current.path}/portix-serv/target/release/$libraryName',
    '${File(Platform.resolvedExecutable).parent.path}/$libraryName',
  ];

  for (final candidate in candidates) {
    if (File(candidate).existsSync()) return File(candidate).absolute.path;
  }
  return null;
}
