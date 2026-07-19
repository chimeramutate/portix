import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/connection_manager/connection_backend.dart';
import 'package:portix/src/connection_manager/connection_manager.dart';
import 'package:portix/src/connection_manager/session_models.dart';
import 'package:portix/src/connection_manager/ssh_profile.dart';
import 'package:portix/src/data/services/sftp/local_editor_service.dart';
import 'package:portix/src/data/services/sftp/local_file_browser.dart';
import 'package:portix/src/domain/entities/sftp/sftp_file_entry.dart';
import 'package:portix/src/domain/entities/ssh/ssh_profile.dart' as domain;
import 'package:portix/src/features/sftp/controller/sftp_workspace_controller.dart';

void main() {
  group('SftpWorkspaceController remote open regression', () {
    late _FakeConnectionBackend backend;
    late ConnectionManager connectionManager;
    late SftpWorkspaceController controller;

    setUp(() {
      backend = _FakeConnectionBackend();
      connectionManager = ConnectionManager(backend: backend);
      controller = SftpWorkspaceController(
        connectionManager: connectionManager,
        localFileBrowser: _FakeLocalFileBrowser(),
        localEditorService: _FakeLocalEditorService(),
      );
    });

    tearDown(() {
      controller.dispose();
      connectionManager.dispose();
      backend.dispose();
    });

    test('downloads latest bytes into a unique temp file for a remote open', () async {
      await _attachRemoteProfile(controller);
      const remotePath = '/srv/app/config.json';
      final remoteFile = SftpFileEntry(
        name: 'config.json',
        path: remotePath,
        size: '12 B',
        modified: 'Today 12:00',
      );

      backend.remoteFiles[remotePath] = utf8.encode('{"version":1}');
      final firstLocalPath = await controller.editablePathFor(remoteFile, true);
      final firstContent = await File(firstLocalPath).readAsString();

      backend.remoteFiles[remotePath] = utf8.encode('{"version":2}');
      final secondLocalPath = await controller.editablePathFor(remoteFile, true);
      final secondContent = await File(secondLocalPath).readAsString();

      expect(firstLocalPath, isNot(secondLocalPath));
      expect(firstLocalPath, endsWith('.json'));
      expect(secondLocalPath, endsWith('.json'));
      expect(firstContent, '{"version":1}');
      expect(secondContent, '{"version":2}');
      expect(await File(firstLocalPath).exists(), isTrue);
      expect(await File(secondLocalPath).exists(), isTrue);
      expect(backend.readRemoteFileBytesCalls, [remotePath, remotePath]);
    });

    test('same basename from different remote paths never collides locally', () async {
      await _attachRemoteProfile(controller);
      const firstRemotePath = '/srv/a/config.json';
      const secondRemotePath = '/srv/b/config.json';
      final firstFile = SftpFileEntry(
        name: 'config.json',
        path: firstRemotePath,
        size: '10 B',
        modified: 'Today 12:00',
      );
      final secondFile = SftpFileEntry(
        name: 'config.json',
        path: secondRemotePath,
        size: '10 B',
        modified: 'Today 12:00',
      );

      backend.remoteFiles[firstRemotePath] = utf8.encode('alpha');
      backend.remoteFiles[secondRemotePath] = utf8.encode('beta');

      final firstLocalPath = await controller.editablePathFor(firstFile, true);
      final secondLocalPath = await controller.editablePathFor(secondFile, true);

      expect(firstLocalPath, isNot(secondLocalPath));
      expect(await File(firstLocalPath).readAsString(), 'alpha');
      expect(await File(secondLocalPath).readAsString(), 'beta');
      expect(pathBasename(firstLocalPath), isNot(pathBasename(secondLocalPath)));
      expect(backend.readRemoteFileBytesCalls, [firstRemotePath, secondRemotePath]);
      expect(controller.hasRemoteSession, isTrue);
    });

    test('non-remote open returns original local path without backend download', () async {
      final localFile = File('${Directory.systemTemp.path}${Platform.pathSeparator}portix-local-${DateTime.now().microsecondsSinceEpoch}.txt');
      await localFile.writeAsString('local');
      final localEntry = SftpFileEntry(
        name: pathBasename(localFile.path),
        path: localFile.path,
        size: '5 B',
        modified: 'Today 12:00',
      );

      final resolvedPath = await controller.editablePathFor(localEntry, false);

      expect(resolvedPath, localFile.path);
      expect(backend.readRemoteFileBytesCalls, isEmpty);
      await localFile.delete();
    });

    test('throws when remote session is missing before remote open', () async {
      final remoteFile = SftpFileEntry(
        name: 'config.json',
        path: '/srv/app/config.json',
        size: '12 B',
        modified: 'Today 12:00',
      );

      await expectLater(
        () => controller.editablePathFor(remoteFile, true),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Remote SFTP session is not connected'),
          ),
        ),
      );
      expect(backend.readRemoteFileBytesCalls, isEmpty);
    });

    test('propagates backend read failures and does not leave a partial local file', () async {
      await _attachRemoteProfile(controller);
      const remotePath = '/srv/app/missing.json';
      final remoteFile = SftpFileEntry(
        name: 'missing.json',
        path: remotePath,
        size: '0 B',
        modified: 'Today 12:00',
      );
      backend.readErrorPaths.add(remotePath);

      await expectLater(
        () => controller.editablePathFor(remoteFile, true),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('Failed to download remote file'),
          ),
        ),
      );
      expect(backend.readRemoteFileBytesCalls, [remotePath]);
    });

    test('supports filenames without extension and still generates unique local paths', () async {
      await _attachRemoteProfile(controller);
      const remotePath = '/opt/bin/env';
      final remoteFile = SftpFileEntry(
        name: 'env',
        path: remotePath,
        size: '8 B',
        modified: 'Today 12:00',
      );
      backend.remoteFiles[remotePath] = utf8.encode('KEY=one');

      final firstLocalPath = await controller.editablePathFor(remoteFile, true);
      await Future<void>.delayed(const Duration(milliseconds: 2));
      final secondLocalPath = await controller.editablePathFor(remoteFile, true);

      expect(pathBasename(firstLocalPath), startsWith('env__'));
      expect(pathBasename(secondLocalPath), startsWith('env__'));
      expect(pathBasename(firstLocalPath), isNot(pathBasename(secondLocalPath)));
    });
  });
}

Future<String> _attachRemoteProfile(SftpWorkspaceController controller) async {
  const profile = domain.SshProfile(
    id: 'profile-1',
    name: 'Remote host',
    host: 'example.com',
    port: 22,
    username: 'deploy',
    group: 'Production',
    tags: [],
    authMethod: domain.AuthMethod.sshKey,
    credentialLabel: '~/.ssh/id_ed25519',
    defaultPath: '/',
    status: domain.ConnectionStatus.online,
    color: domain.ProfileColor.blue,
  );
  await controller.attachRemoteProfile(profile, '/');
  expect(controller.hasRemoteSession, isTrue);
  expect(controller.remotePath, '/');
  return controller.remotePath;
}

String pathBasename(String path) => path.split(Platform.pathSeparator).last;

class _FakeLocalEditorService extends LocalEditorService {}

class _FakeLocalFileBrowser extends LocalFileBrowser {
  @override
  String defaultPath() => Directory.systemTemp.path;

  @override
  Future<LocalDirectoryResult> readDirectory(String path) async {
    return LocalDirectoryResult(path: path, entries: const []);
  }
}

class _FakeConnectionBackend implements ConnectionBackend {
  final _output = StreamController<TerminalOutputEvent>.broadcast();
  final _status = StreamController<ConnectionStatusEvent>.broadcast();
  final _errors = StreamController<ConnectionErrorEvent>.broadcast();
  final Map<String, List<int>> remoteFiles = {};
  final List<String> readRemoteFileBytesCalls = [];
  final Set<String> readErrorPaths = {};
  int _sessionCounter = 0;

  @override
  Stream<TerminalOutputEvent> get terminalOutputStream => _output.stream;

  @override
  Stream<ConnectionStatusEvent> get connectionStatusStream => _status.stream;

  @override
  Stream<ConnectionErrorEvent> get errorEventStream => _errors.stream;

  @override
  Future<String> connect(SshProfile profile) async {
    _sessionCounter += 1;
    final sessionId = 'fake-sftp-$_sessionCounter';
    _status.add(
      ConnectionStatusEvent(
        sessionId: sessionId,
        status: ConnectionStatus.connected,
      ),
    );
    return sessionId;
  }

  @override
  Future<void> disconnect(String sessionId) async {
    _status.add(
      ConnectionStatusEvent(
        sessionId: sessionId,
        status: ConnectionStatus.disconnected,
      ),
    );
  }

  @override
  Future<List<int>> readRemoteFileBytes(String sessionId, String path) async {
    readRemoteFileBytesCalls.add(path);
    if (readErrorPaths.contains(path)) {
      throw StateError('simulated remote read failure for $path');
    }
    final data = remoteFiles[path];
    if (data == null) {
      throw StateError('remote file missing: $path');
    }
    return List<int>.from(data);
  }

  @override
  Future<String> resolveRemoteDirectory(String sessionId, String path) async => path;

  @override
  Future<List<RemoteFileEntry>> listRemoteDirectory(String sessionId, String path) async => const [];

  @override
  Future<String> readRemoteFile(String sessionId, String path) async {
    final bytes = await readRemoteFileBytes(sessionId, path);
    return utf8.decode(bytes);
  }

  @override
  Future<void> writeRemoteFile(String sessionId, String path, String content) async {
    remoteFiles[path] = utf8.encode(content);
  }

  @override
  Future<void> uploadRemoteFile(String sessionId, String path, List<int> data) async {
    remoteFiles[path] = List<int>.from(data);
  }

  @override
  Future<void> createRemoteDirectory(String sessionId, String path) async {}

  @override
  Future<void> createRemoteFile(String sessionId, String path) async {
    remoteFiles.putIfAbsent(path, () => <int>[]);
  }

  @override
  Future<void> chmodRemotePath(String sessionId, String path, String mode) async {}

  @override
  Future<void> resizeTerminal(String sessionId, int cols, int rows) async {}

  @override
  Future<RemoteSystemSnapshot> remoteSystemSnapshot(String sessionId) async {
    return const RemoteSystemSnapshot(
      os: 'linux',
      hostname: 'fake-host',
      uptime: '1 day',
      memory: '1 GB',
      disk: '10 GB',
    );
  }

  @override
  Future<List<String>> commandHelpSuggestions(String sessionId, String input) async => const [];

  @override
  Future<List<TerminalCompletionCandidate>> commandCompletions(String sessionId, String input) async => const [];

  @override
  Future<TerminalCompleteResponse> terminalComplete(TerminalCompleteRequest request) async {
    return const TerminalCompleteResponse(items: []);
  }

  @override
  Future<void> sendTerminalInput(String sessionId, String data) async {}

  void dispose() {
    _output.close();
    _status.close();
    _errors.close();
  }
}
