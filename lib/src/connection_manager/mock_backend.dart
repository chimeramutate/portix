import 'dart:async';

import 'connection_backend.dart';
import 'session_models.dart';
import 'ssh_profile.dart';

class MockConnectionBackend implements ConnectionBackend {
  final _output = StreamController<TerminalOutputEvent>.broadcast();
  final _status = StreamController<ConnectionStatusEvent>.broadcast();
  final _errors = StreamController<ConnectionErrorEvent>.broadcast();

  @override
  Stream<TerminalOutputEvent> get terminalOutputStream => _output.stream;

  @override
  Stream<ConnectionStatusEvent> get connectionStatusStream => _status.stream;

  @override
  Stream<ConnectionErrorEvent> get errorEventStream => _errors.stream;

  @override
  Future<String> connect(SshProfile profile) async {
    final sessionId = 'local-${DateTime.now().microsecondsSinceEpoch}';
    _status.add(
      ConnectionStatusEvent(
        sessionId: sessionId,
        status: ConnectionStatus.connecting,
        message: 'Connecting to ${profile.host}:${profile.port}',
      ),
    );
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 500), () {
        if (_status.isClosed || _output.isClosed) return;
        _status.add(
          ConnectionStatusEvent(
            sessionId: sessionId,
            status: ConnectionStatus.connected,
            message: 'Connected',
          ),
        );
        _output.add(
          TerminalOutputEvent(
            sessionId: sessionId,
            data: '${profile.username}@${profile.name}:~\$ ',
          ),
        );
      }),
    );
    return sessionId;
  }

  @override
  Future<void> disconnect(String sessionId) async {
    _output.add(
      TerminalOutputEvent(sessionId: sessionId, data: '\r\n[disconnected]\r\n'),
    );
    _status.add(
      ConnectionStatusEvent(
        sessionId: sessionId,
        status: ConnectionStatus.disconnected,
      ),
    );
  }

  @override
  Future<void> resizeTerminal(String sessionId, int cols, int rows) async {}

  @override
  Future<RemoteSystemSnapshot> remoteSystemSnapshot(String sessionId) async {
    throw UnsupportedError(
      'Remote telemetry is available only on Rust backend',
    );
  }

  @override
  Future<List<String>> commandHelpSuggestions(
    String sessionId,
    String input,
  ) async {
    final completions = await commandCompletions(sessionId, input);
    return completions.map((candidate) => candidate.replacement).toList();
  }

  @override
  Future<List<TerminalCompletionCandidate>> commandCompletions(
    String sessionId,
    String input,
  ) async {
    final normalized = input.trimLeft().toLowerCase();
    final current = normalized.split(RegExp(r'\s+')).last;
    if (normalized.startsWith('git')) {
      return const [
            TerminalCompletionCandidate(
              replacement: 'git pull',
              display: 'pull',
              description: 'fetch from and merge with another repository',
              source: 'help',
            ),
            TerminalCompletionCandidate(
              replacement: 'git push',
              display: 'push',
              description: 'update remote refs along with associated objects',
              source: 'help',
            ),
            TerminalCompletionCandidate(
              replacement: 'git --force-with-lease',
              display: '--force-with-lease',
              description:
                  'require old value of the remote ref to be unchanged',
              source: 'help',
            ),
          ]
          .where(
            (candidate) =>
                current.isEmpty ||
                candidate.display.toLowerCase().startsWith(current) ||
                candidate.replacement.toLowerCase().startsWith(normalized),
          )
          .toList(growable: false);
    }
    if (normalized.startsWith('docker')) {
      return const [
        TerminalCompletionCandidate(
          replacement: 'docker ps',
          display: 'ps',
          description: 'list containers',
          source: 'help',
        ),
        TerminalCompletionCandidate(
          replacement: 'docker compose',
          display: 'compose',
          description: 'Docker Compose command group',
          source: 'help',
        ),
      ];
    }
    return const [];
  }

  @override
  Future<TerminalCompleteResponse> terminalComplete(
    TerminalCompleteRequest request,
  ) async {
    final input = request.buffer.trimLeft().toLowerCase();
    final maxItems = request.maxItems ?? 8;
    const items = [
      TerminalCompletionItem(
        label: 'ls',
        insertText: 'ls',
        kind: CompletionKind.command,
        description: 'list directory contents',
        score: 90,
      ),
      TerminalCompletionItem(
        label: '-la',
        insertText: '-la',
        kind: CompletionKind.command,
        description: 'long format including hidden files',
        score: 85,
      ),
      TerminalCompletionItem(
        label: '--help',
        insertText: '--help',
        kind: CompletionKind.command,
        description: 'show command help',
        score: 80,
      ),
      TerminalCompletionItem(
        label: 'git status',
        insertText: 'git status',
        kind: CompletionKind.history,
        description: 'recent command',
        score: 70,
      ),
      TerminalCompletionItem(
        label: r'$HOME',
        insertText: r'$HOME',
        kind: CompletionKind.env,
        description: 'environment variable',
        score: 65,
      ),
    ];
    final filtered = items
        .where(
          (item) =>
              input.isEmpty ||
              item.label.toLowerCase().startsWith(input.split(' ').last) ||
              item.insertText.toLowerCase().startsWith(input.split(' ').last),
        )
        .take(maxItems)
        .toList(growable: false);
    return TerminalCompleteResponse(
      suggestion: input == 'git st' ? 'atus' : null,
      items: filtered,
    );
  }

  @override
  Future<String> resolveRemoteDirectory(String sessionId, String path) async {
    return path;
  }

  @override
  Future<List<RemoteFileEntry>> listRemoteDirectory(
    String sessionId,
    String path,
  ) async {
    throw UnsupportedError('Remote folders are available only on Rust backend');
  }

  @override
  Future<String> readRemoteFile(String sessionId, String path) async {
    throw UnsupportedError('Remote files are available only on Rust backend');
  }

  @override
  Future<List<int>> readRemoteFileBytes(String sessionId, String path) async {
    throw UnsupportedError('Remote files are available only on Rust backend');
  }

  @override
  Future<void> writeRemoteFile(
    String sessionId,
    String path,
    String content,
  ) async {
    throw UnsupportedError('Remote files are available only on Rust backend');
  }

  @override
  Future<void> uploadRemoteFile(
    String sessionId,
    String path,
    List<int> data,
  ) async {
    throw UnsupportedError('Remote upload is available only on Rust backend');
  }

  @override
  Future<void> createRemoteDirectory(String sessionId, String path) async {
    throw UnsupportedError('Remote folders are available only on Rust backend');
  }

  @override
  Future<void> createRemoteFile(String sessionId, String path) async {
    throw UnsupportedError('Remote files are available only on Rust backend');
  }

  @override
  Future<void> chmodRemotePath(
    String sessionId,
    String path,
    String mode,
  ) async {
    throw UnsupportedError('Remote chmod is available only on Rust backend');
  }

  @override
  Future<void> sendTerminalInput(String sessionId, String data) async {
    for (final char in data.codeUnits) {
      switch (char) {
        case 8: // Ctrl+H / backspace
        case 127: // DEL / delete as sent by most terminals
          _output.add(TerminalOutputEvent(sessionId: sessionId, data: '\b \b'));
        case 13: // carriage return
          _output.add(
            TerminalOutputEvent(sessionId: sessionId, data: '\r\n\$ '),
          );
        default:
          _output.add(
            TerminalOutputEvent(
              sessionId: sessionId,
              data: String.fromCharCode(char),
            ),
          );
      }
    }
  }

  void dispose() {
    _output.close();
    _status.close();
    _errors.close();
  }
}
