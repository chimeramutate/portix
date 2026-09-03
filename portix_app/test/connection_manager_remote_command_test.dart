import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/connection_manager/connection_backend.dart';
import 'package:portix/src/connection_manager/connection_manager.dart';
import 'package:portix/src/connection_manager/session_models.dart';
import 'package:portix/src/connection_manager/ssh_profile.dart';
import 'package:portix/src/core/result/either.dart';

/// Regression test for the "SFTP commands leak into the remote shell history"
/// bug. SFTP file-management operations (rename/move/delete/duplicate) must run
/// on the session's DEDICATED exec channel (`execRemoteCommand`) and must NOT be
/// sent through `sendTerminalInput` (the interactive shell), which previously
/// recorded the wrapped `mv`/`rm` command — including the `__PORTIX_CMD_…_EXIT`
/// marker wrapper — into the remote shell's shared `HISTFILE`.
void main() {
  group('ConnectionManager.executeRemoteCommand', () {
    late _RecordingBackend backend;
    late ConnectionManager manager;
    late String uiSessionId;

    setUp(() async {
      backend = _RecordingBackend();
      manager = ConnectionManager(backend: backend);
      final result = await manager.connect(
        SshProfile(
          id: 'p1',
          name: 'host',
          host: 'example.com',
          port: 22,
          username: 'deploy',
        ),
      );
      // The fake emits a connected status event during connect(); after
      // _connect registers `_backendToUiSessionIds`, the UI session is available.
      expect(result, isA<Right>());
      uiSessionId = manager.sessions.first.id;
    });

    tearDown(() {
      manager.dispose();
      backend.dispose();
    });

    test('routes the command through the dedicated exec channel', () async {
      final result = await manager.executeRemoteCommand(
        uiSessionId,
        "mv -- '/srv/a.txt' '/srv/b.txt'",
        action: 'rename remote path',
      );

      expect(result, isA<Right>());
      expect(backend.execRemoteCommandCalls, hasLength(1));
      expect(backend.execRemoteCommandCalls.first.sessionId, 'backend-ssh-1');
      expect(backend.execRemoteCommandCalls.first.command,
          "mv -- '/srv/a.txt' '/srv/b.txt'");
    });

    test("does not send the command (or any marker) through the terminal",
        () async {
      await manager.executeRemoteCommand(
        uiSessionId,
        "mv -- '/srv/a.txt' '/srv/b.txt'",
        action: 'rename remote path',
      );

      // No terminal input should be produced at all: the command must not reach
      // the interactive shell, so it can never be recorded in shell history.
      expect(backend.sendTerminalInputCalls, isEmpty);
      expect(backend.sentTerminalInput, isEmpty);
    });

    test('forwards a concise success summary to the SSH terminal panel', () async {
      final output = <TerminalOutputEvent>[];
      manager.terminalOutputStream.listen(output.add);

      await manager.executeRemoteCommand(
        uiSessionId,
        'rm -rf -- /tmp/x',
        action: 'delete remote path',
      );

      // StreamController.broadcast() delivers events asynchronously (sync:
      // false), so flush the microtask queue before asserting.
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      // A clean summary line (green ✓) is shown, but never the raw command,
      // the wrapping `{ ...; }`, or the `__PORTIX_CMD` marker.
      final combined = output.map((e) => e.data).join();
      expect(combined, contains('[portix] delete remote path'));
      expect(combined, contains('✓'));
      expect(combined, isNot(contains('__PORTIX_CMD')));
      expect(combined, isNot(contains('rm -rf')));
    });

    test('surfaces backend failures as a Left without touching the terminal',
        () async {
      backend.execError = StateError('remote command exited with 1: boom');

      final result = await manager.executeRemoteCommand(
        uiSessionId,
        'rm -rf -- /srv/missing',
        action: 'delete remote path',
      );

      expect(result, isA<Left>());
      // The command never reached the interactive shell.
      expect(backend.sendTerminalInputCalls, isEmpty);
    });
  });
}

class _ExecCall {
  final String sessionId;
  final String command;
  _ExecCall(this.sessionId, this.command);
}

class _RecordingBackend implements ConnectionBackend {
  final _output = StreamController<TerminalOutputEvent>.broadcast();
  final _status = StreamController<ConnectionStatusEvent>.broadcast();
  final _errors = StreamController<ConnectionErrorEvent>.broadcast();

  final List<_ExecCall> execRemoteCommandCalls = [];
  final List<String> sentTerminalInput = [];
  final List<({String sessionId, String data})> sendTerminalInputCalls = [];
  Object? execError;

  String? _nextSessionId;

  @override
  Stream<TerminalOutputEvent> get terminalOutputStream => _output.stream;

  @override
  Stream<ConnectionStatusEvent> get connectionStatusStream => _status.stream;

  @override
  Stream<ConnectionErrorEvent> get errorEventStream => _errors.stream;

  @override
  Future<String> connect(SshProfile profile) async {
    final sessionId = 'backend-ssh-1';
    _nextSessionId = sessionId;
    _status.add(ConnectionStatusEvent(sessionId: sessionId, status: ConnectionStatus.connected));
    return sessionId;
  }

  @override
  Future<void> disconnect(String sessionId) async {
    _status.add(ConnectionStatusEvent(sessionId: sessionId, status: ConnectionStatus.disconnected));
  }

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
  Future<List<String>> commandHelpSuggestions(String sessionId, String input) async =>
      const [];

  @override
  Future<List<TerminalCompletionCandidate>> commandCompletions(
    String sessionId,
    String input,
  ) async => const [];

  @override
  Future<TerminalCompleteResponse> terminalComplete(
    TerminalCompleteRequest request,
  ) async => const TerminalCompleteResponse(items: []);

  @override
  Future<String> resolveRemoteDirectory(String sessionId, String path) async => path;

  @override
  Future<List<RemoteFileEntry>> listRemoteDirectory(
    String sessionId,
    String path,
  ) async => const [];

  @override
  Future<String> readRemoteFile(String sessionId, String path) async => '';

  @override
  Future<List<int>> readRemoteFileBytes(
    String sessionId,
    String path,
  ) async => const [];

  @override
  Future<void> writeRemoteFile(
    String sessionId,
    String path,
    String content,
  ) async {}

  @override
  Future<void> uploadRemoteFile(
    String sessionId,
    String path,
    List<int> data,
  ) async {}

  @override
  Future<void> createRemoteDirectory(String sessionId, String path) async {}

  @override
  Future<void> createRemoteFile(String sessionId, String path) async {}

  @override
  Future<void> chmodRemotePath(
    String sessionId,
    String path,
    String mode,
  ) async {}

  @override
  Future<void> sendTerminalInput(String sessionId, String data) async {
    sentTerminalInput.add(data);
    sendTerminalInputCalls.add((sessionId: sessionId, data: data));
  }

  @override
  Future<String> execRemoteCommand(String sessionId, String command) async {
    execRemoteCommandCalls.add(_ExecCall(sessionId, command));
    if (execError != null) {
      throw execError!;
    }
    return '';
  }

  void dispose() {
    _output.close();
    _status.close();
    _errors.close();
  }
}
