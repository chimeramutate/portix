import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/connection_manager/connection_backend.dart';
import 'package:portix/src/connection_manager/connection_manager.dart';
import 'package:portix/src/connection_manager/session_models.dart';
import 'package:portix/src/connection_manager/ssh_profile.dart';
import 'package:portix/src/core/result/either.dart';
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

    test(
      'downloads latest bytes into a unique temp file for a remote open',
      () async {
        await _attachRemoteProfile(controller);
        const remotePath = '/srv/app/config.json';
        final remoteFile = SftpFileEntry(
          name: 'config.json',
          path: remotePath,
          size: '12 B',
          modified: 'Today 12:00',
        );

        backend.remoteFiles[remotePath] = utf8.encode('{"version":1}');
        final firstLocalPath = await controller.editablePathFor(
          remoteFile,
          true,
        );
        final firstContent = await File(firstLocalPath).readAsString();

        backend.remoteFiles[remotePath] = utf8.encode('{"version":2}');
        final secondLocalPath = await controller.editablePathFor(
          remoteFile,
          true,
        );
        final secondContent = await File(secondLocalPath).readAsString();

        expect(firstLocalPath, isNot(secondLocalPath));
        expect(firstLocalPath, endsWith('.json'));
        expect(secondLocalPath, endsWith('.json'));
        expect(firstContent, '{"version":1}');
        expect(secondContent, '{"version":2}');
        expect(await File(firstLocalPath).exists(), isTrue);
        expect(await File(secondLocalPath).exists(), isTrue);
        expect(backend.readRemoteFileBytesCalls, [remotePath, remotePath]);
      },
    );

    test(
      'same basename from different remote paths never collides locally',
      () async {
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

        final firstLocalPath = await controller.editablePathFor(
          firstFile,
          true,
        );
        final secondLocalPath = await controller.editablePathFor(
          secondFile,
          true,
        );

        expect(firstLocalPath, isNot(secondLocalPath));
        expect(await File(firstLocalPath).readAsString(), 'alpha');
        expect(await File(secondLocalPath).readAsString(), 'beta');
        expect(
          pathBasename(firstLocalPath),
          isNot(pathBasename(secondLocalPath)),
        );
        expect(backend.readRemoteFileBytesCalls, [
          firstRemotePath,
          secondRemotePath,
        ]);
        expect(controller.hasRemoteSession, isTrue);
      },
    );

    test(
      'non-remote open returns original local path without backend download',
      () async {
        final localFile = File(
          '${Directory.systemTemp.path}${Platform.pathSeparator}portix-local-${DateTime.now().microsecondsSinceEpoch}.txt',
        );
        await localFile.writeAsString('local');
        final localEntry = SftpFileEntry(
          name: pathBasename(localFile.path),
          path: localFile.path,
          size: '5 B',
          modified: 'Today 12:00',
        );

        final resolvedPath = await controller.editablePathFor(
          localEntry,
          false,
        );

        expect(resolvedPath, localFile.path);
        expect(backend.readRemoteFileBytesCalls, isEmpty);
        await localFile.delete();
      },
    );

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

    test(
      'propagates backend read failures and does not leave a partial local file',
      () async {
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
      },
    );

    test(
      'supports filenames without extension and still generates unique local paths',
      () async {
        await _attachRemoteProfile(controller);
        const remotePath = '/opt/bin/env';
        final remoteFile = SftpFileEntry(
          name: 'env',
          path: remotePath,
          size: '8 B',
          modified: 'Today 12:00',
        );
        backend.remoteFiles[remotePath] = utf8.encode('KEY=one');

        final firstLocalPath = await controller.editablePathFor(
          remoteFile,
          true,
        );
        await Future<void>.delayed(const Duration(milliseconds: 2));
        final secondLocalPath = await controller.editablePathFor(
          remoteFile,
          true,
        );

        expect(pathBasename(firstLocalPath), startsWith('env__'));
        expect(pathBasename(secondLocalPath), startsWith('env__'));
        expect(
          pathBasename(firstLocalPath),
          isNot(pathBasename(secondLocalPath)),
        );
      },
    );

    test(
      'shouldNotifyDisconnection is false when SFTP session is connected',
      () async {
        await _attachRemoteProfile(controller);
        expect(controller.shouldNotifyDisconnection, isFalse);
        expect(controller.isRemoteConnected, isTrue);
      },
    );

    test(
      'shouldNotifyDisconnection is false after clearRemoteSession',
      () async {
        await _attachRemoteProfile(controller);
        expect(controller.shouldNotifyDisconnection, isFalse);

        await controller.clearRemoteSession();
        expect(controller.shouldNotifyDisconnection, isFalse);
        expect(controller.hasRemoteSession, isFalse);
      },
    );

    test(
      'shouldNotifyDisconnection becomes true when backend drops the session',
      () async {
        await _attachRemoteProfile(controller);
        expect(controller.shouldNotifyDisconnection, isFalse);

        // Simulate the Rust backend losing the SSH/SFTP channel (keepalive
        // timeout or remote-side disconnect).
        backend.emitStatus(
          controller.remoteSessionId,
          ConnectionStatus.disconnected,
        );
        await Future.delayed(Duration.zero);
        await Future.delayed(Duration.zero);

        expect(controller.shouldNotifyDisconnection, isTrue);
      },
    );

    test(
      'clearDisconnectionNotification resets the flag so reconnect is clean',
      () async {
        await _attachRemoteProfile(controller);
        backend.emitStatus(
          controller.remoteSessionId,
          ConnectionStatus.disconnected,
        );
        await Future.delayed(Duration.zero);
        await Future.delayed(Duration.zero);
        expect(controller.shouldNotifyDisconnection, isTrue);

        controller.clearDisconnectionNotification();
        expect(controller.shouldNotifyDisconnection, isFalse);
      },
    );

    test(
      'clearRemoteSession removes the SFTP session from the connection manager',
      () async {
        await _attachRemoteProfile(controller);
        final sessionId = controller.remoteSessionId;
        expect(sessionId, isNotNull);
        expect(connectionManager.sessions, isNotEmpty);

        await controller.clearRemoteSession();
        await Future.delayed(Duration.zero);
        await Future.delayed(Duration.zero);

        expect(
          connectionManager.sessions.any((s) => s.id == sessionId),
          isFalse,
        );
        expect(controller.hasRemoteSession, isFalse);
        expect(controller.shouldNotifyDisconnection, isFalse);
      },
    );

    test('SFTP sessions are excluded from the heartbeat TCP probe', () async {
      // Use a profile with an unreachable host (127.0.0.1:1 is a closed port
      // that refuses TCP immediately) and UPSERT it so the heartbeat can find
      // the profile. An SSH session to this host should be marked as dead by
      // the heartbeat, but an SFTP session must remain connected because SFTP
      // sessions are excluded from the TCP probe (they ride on the Rust-managed
      // keepalive).
      final unreachableProfile = SshProfile(
        id: 'p-unreachable',
        name: 'unreachable',
        host: '127.0.0.1',
        port: 1,
        username: 'deploy',
      );

      // SSH session — should be probed and killed by heartbeat.
      final sshResult = await connectionManager.connect(unreachableProfile);
      expect(sshResult, isA<Right>());
      connectionManager.upsertProfile(unreachableProfile);

      // Give the deferred status event time to propagate.
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      final sshSession = connectionManager.sessions
          .where((s) => s.kind == SessionKind.ssh)
          .first;
      expect(sshSession.status, equals(ConnectionStatus.connected));

      // SFTP session — should NOT be probed by heartbeat.
      final sftpResult = await connectionManager.connectSftp(
        unreachableProfile,
      );
      expect(sftpResult, isA<Right>());

      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      final sftpSession = connectionManager.sessions
          .where((s) => s.kind == SessionKind.sftp)
          .first;
      expect(sftpSession.status, equals(ConnectionStatus.connected));

      // Wait for the heartbeat timer to fire (5 s interval) and the TCP
      // probe to complete. With 127.0.0.1:1 the connection-refused error is
      // immediate, so 7 s is plenty.
      await Future.delayed(const Duration(seconds: 7));

      // SSH session: the heartbeat TCP probe to the unreachable host should
      // have killed it — _markSessionDead first sets it to "error" and then
      // calls _backend.disconnect(), which the fake backend turns into a
      // "disconnected" status event. The net final status is therefore
      // "disconnected" (no longer connected).
      final updatedSshSession = connectionManager.sessions.firstWhere(
        (s) => s.id == sshSession.id,
      );
      expect(
        updatedSshSession.status,
        isNot(equals(ConnectionStatus.connected)),
        reason: 'SSH session should have been killed by the heartbeat probe',
      );

      // SFTP session: must remain connected because SFTP sessions are
      // excluded from the heartbeat candidate list.
      final updatedSftpSession = connectionManager.sessions.firstWhere(
        (s) => s.id == sftpSession.id,
      );
      expect(updatedSftpSession.status, equals(ConnectionStatus.connected));
    });

    test('per-tab tabId is unique and defaults to a non-empty UUID', () async {
      final firstController = SftpWorkspaceController(
        connectionManager: connectionManager,
      );
      final secondController = SftpWorkspaceController(
        connectionManager: connectionManager,
      );

      expect(firstController.tabId, isNotEmpty);
      expect(secondController.tabId, isNotEmpty);
      expect(firstController.tabId, isNot(equals(secondController.tabId)));

      firstController.dispose();
      secondController.dispose();
    });

    test(
      'two controllers on one ConnectionManager are session-isolated',
      () async {
        // Proves the foundation for an independent left-pane SSH session:
        // two controllers sharing the singleton ConnectionManager must each
        // own a distinct SFTP session that the other cannot clear or corrupt.
        // The controller's connection-change listener (`_handleConnectionManager
        // Changed`) early-returns when its own `_remoteSessionId` is null and
        // otherwise only inspects the session matching that id, so a status
        // event on A's session never bleeds into B (and vice-versa).
        final controllerA = SftpWorkspaceController(
          connectionManager: connectionManager,
          localFileBrowser: _FakeLocalFileBrowser(),
          localEditorService: _FakeLocalEditorService(),
        );
        final controllerB = SftpWorkspaceController(
          connectionManager: connectionManager,
          localFileBrowser: _FakeLocalFileBrowser(),
          localEditorService: _FakeLocalEditorService(),
        );

        final profileA = domain.SshProfile(
          id: 'profile-a',
          name: 'Host A',
          host: 'a.example.com',
          port: 22,
          username: 'deploy',
          group: 'Production',
          tags: [],
          authMethod: domain.AuthMethod.sshKey,
          credentialLabel: '~/.ssh/id_ed25519',
          defaultPath: '/srv/app',
          status: domain.ConnectionStatus.online,
          color: domain.ProfileColor.blue,
        );
        final profileB = domain.SshProfile(
          id: 'profile-b',
          name: 'Host B',
          host: 'b.example.com',
          port: 22,
          username: 'deploy',
          group: 'Production',
          tags: [],
          authMethod: domain.AuthMethod.sshKey,
          credentialLabel: '~/.ssh/id_ed25519',
          defaultPath: '/opt/data',
          status: domain.ConnectionStatus.online,
          color: domain.ProfileColor.green,
        );

        await controllerA.attachRemoteProfile(profileA, '/srv/app');
        await controllerB.attachRemoteProfile(profileB, '/opt/data');
        await Future.delayed(Duration.zero);
        await Future.delayed(Duration.zero);

        // Both sessions are live and distinct.
        expect(controllerA.hasRemoteSession, isTrue);
        expect(controllerB.hasRemoteSession, isTrue);
        expect(controllerA.remoteSessionId, isNotNull);
        expect(controllerB.remoteSessionId, isNotNull);
        expect(
          controllerA.remoteSessionId,
          isNot(equals(controllerB.remoteSessionId)),
        );
        expect(controllerA.remotePath, '/srv/app');
        expect(controllerB.remotePath, '/opt/data');
        expect(controllerA.isRemoteConnected, isTrue);
        expect(controllerB.isRemoteConnected, isTrue);

        // Clearing A leaves B fully intact (true session isolation).
        await controllerA.clearRemoteSession();
        await Future.delayed(Duration.zero);
        await Future.delayed(Duration.zero);

        expect(controllerA.hasRemoteSession, isFalse);
        expect(controllerA.remoteSessionId, isNull);
        expect(controllerA.shouldNotifyDisconnection, isFalse);
        expect(controllerB.hasRemoteSession, isTrue);
        expect(controllerB.isRemoteConnected, isTrue);
        expect(controllerB.remoteSessionId, isNotNull);
        expect(controllerB.remotePath, '/opt/data');

        controllerA.dispose();
        controllerB.dispose();
      },
    );
  });

  test('notifyListeners after dispose is a no-op (tab/page close safety)', () {
    final backend = _FakeConnectionBackend();
    final connectionManager = ConnectionManager(backend: backend);
    final controller = SftpWorkspaceController(
      connectionManager: connectionManager,
      localFileBrowser: _FakeLocalFileBrowser(),
      localEditorService: _FakeLocalEditorService(),
    );
    // The constructor starts an in-flight loadLocalDirectory; disposing while
    // it is pending (i.e. closing/popping the SFTP tab) must let any resumed
    // notifyListeners fire safely instead of tripping the
    // "used after being disposed" ChangeNotifier assert.
    controller.dispose();
    expect(() => controller.notifyListeners(), returnsNormally);
    connectionManager.dispose();
    backend.dispose();
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
  // Flush the event/microtask queue so the backend's deferred status event
  // is processed by ConnectionManager and the session reaches "connected".
  await Future.delayed(Duration.zero);
  await Future.delayed(Duration.zero);
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
    // Defer status delivery so the ConnectionManager has already registered
    // the backend-to-UI session ID mapping before _handleStatus runs.
    // Without this, _handleStatus can't resolve the backend session ID to a
    // UI session ID and the "connected" status is silently dropped.
    Future.delayed(Duration.zero, () {
      _status.add(
        ConnectionStatusEvent(
          sessionId: sessionId,
          status: ConnectionStatus.connected,
        ),
      );
    });
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
  Future<String> resolveRemoteDirectory(String sessionId, String path) async =>
      path;

  @override
  Future<List<RemoteFileEntry>> listRemoteDirectory(
    String sessionId,
    String path,
  ) async => const [];

  @override
  Future<String> readRemoteFile(String sessionId, String path) async {
    final bytes = await readRemoteFileBytes(sessionId, path);
    return utf8.decode(bytes);
  }

  @override
  Future<void> writeRemoteFile(
    String sessionId,
    String path,
    String content,
  ) async {
    remoteFiles[path] = utf8.encode(content);
  }

  @override
  Future<void> uploadRemoteFile(
    String sessionId,
    String path,
    List<int> data,
  ) async {
    remoteFiles[path] = List<int>.from(data);
  }

  @override
  Future<void> createRemoteDirectory(String sessionId, String path) async {}

  @override
  Future<void> createRemoteFile(String sessionId, String path) async {
    remoteFiles.putIfAbsent(path, () => <int>[]);
  }

  @override
  Future<void> chmodRemotePath(
    String sessionId,
    String path,
    String mode,
  ) async {}

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
  Future<List<String>> commandHelpSuggestions(
    String sessionId,
    String input,
  ) async => const [];

  @override
  Future<List<TerminalCompletionCandidate>> commandCompletions(
    String sessionId,
    String input,
  ) async => const [];

  @override
  Future<TerminalCompleteResponse> terminalComplete(
    TerminalCompleteRequest request,
  ) async {
    return const TerminalCompleteResponse(items: []);
  }

  @override
  Future<void> sendTerminalInput(String sessionId, String data) async {}

  @override
  Future<String> execRemoteCommand(String sessionId, String command) async {
    // Default: no-op success with empty output. Tests that need to observe or
    // fail specific commands can override this.
    return '';
  }

  void dispose() {
    _output.close();
    _status.close();
    _errors.close();
  }

  /// Simulates the backend emitting a connection-status update for the given
  /// backend session ID (as returned by [connect]).
  void emitStatus(String? sessionId, ConnectionStatus status) {
    if (sessionId == null) return;
    _status.add(ConnectionStatusEvent(sessionId: sessionId, status: status));
  }
}
