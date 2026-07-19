enum ConnectionStatus { disconnected, connecting, connected, error }

enum SessionKind { ssh, sftp }

enum TerminalColorScheme { portix, matrix, amber, light }

enum CompletionKind { command, path, directory, file, env, git, history }

class TerminalSession {
  const TerminalSession({
    required this.id,
    required this.profileId,
    required this.title,
    required this.status,
    this.kind = SessionKind.ssh,
  });

  final String id;
  final String profileId;
  final String title;
  final ConnectionStatus status;
  final SessionKind kind;

  String get remoteSessionId => id;

  TerminalSession copyWith({
    ConnectionStatus? status,
    String? title,
    SessionKind? kind,
  }) {
    return TerminalSession(
      id: id,
      profileId: profileId,
      title: title ?? this.title,
      status: status ?? this.status,
      kind: kind ?? this.kind,
    );
  }
}

class TerminalSessionDragData {
  const TerminalSessionDragData({
    required this.session,
    this.sourcePaneId,
    this.sourceWorkspaceId,
  });

  final TerminalSession session;
  final String? sourcePaneId;
  final String? sourceWorkspaceId;

  bool get fromWorkspace => sourcePaneId != null || sourceWorkspaceId != null;
}

class TerminalOutputEvent {
  const TerminalOutputEvent({required this.sessionId, required this.data});

  final String sessionId;
  final String data;
}

class SessionLogEntry {
  const SessionLogEntry({
    required this.sessionId,
    required this.kind,
    required this.message,
    required this.createdAt,
  });

  final String sessionId;
  final SessionKind kind;
  final String message;
  final DateTime createdAt;
}

class ConnectionStatusEvent {
  const ConnectionStatusEvent({
    required this.sessionId,
    required this.status,
    this.message,
  });

  final String sessionId;
  final ConnectionStatus status;
  final String? message;
}

class ConnectionErrorEvent {
  const ConnectionErrorEvent({required this.message, this.sessionId});

  final String message;
  final String? sessionId;
}

class RemoteSystemSnapshot {
  const RemoteSystemSnapshot({
    required this.os,
    required this.hostname,
    required this.uptime,
    required this.memory,
    required this.disk,
    this.memoryUsedBytes = 0,
    this.memoryFreeBytes = 0,
    this.memoryTotalBytes = 0,
    this.diskUsedBytes = 0,
    this.diskFreeBytes = 0,
    this.diskTotalBytes = 0,
  });

  final String os;
  final String hostname;
  final String uptime;
  final String memory;
  final String disk;
  final int memoryUsedBytes;
  final int memoryFreeBytes;
  final int memoryTotalBytes;
  final int diskUsedBytes;
  final int diskFreeBytes;
  final int diskTotalBytes;
}

class RemoteFileEntry {
  const RemoteFileEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.sizeBytes,
    this.modifiedUnixSeconds = 0,
  });

  final String name;
  final String path;
  final bool isDirectory;
  final int sizeBytes;
  final int modifiedUnixSeconds;
}

class TerminalCompletionCandidate {
  const TerminalCompletionCandidate({
    required this.replacement,
    required this.display,
    required this.description,
    required this.source,
    this.kind,
  });

  final String replacement;
  final String display;
  final String description;
  final String source;
  final CompletionKind? kind;

  static TerminalCompletionCandidate fromWire(String value) {
    const prefix = 'PORTIX_COMPLETION\t';
    if (!value.startsWith(prefix)) {
      return TerminalCompletionCandidate(
        replacement: value,
        display: value,
        description: '',
        source: 'legacy',
        kind: null,
      );
    }

    final parts = value.substring(prefix.length).split('\t');
    final replacement = parts.isNotEmpty ? parts[0].trim() : '';
    final display = parts.length > 1 ? parts[1].trim() : replacement;
    final description = parts.length > 2 ? parts[2].trim() : '';
    final source = parts.length > 3 ? parts[3].trim() : 'help';
    return TerminalCompletionCandidate(
      replacement: replacement,
      display: display.isEmpty ? replacement : display,
      description: description,
      source: source.isEmpty ? 'help' : source,
      kind: null,
    );
  }
}

class TerminalCompleteRequest {
  const TerminalCompleteRequest({
    required this.buffer,
    required this.cursor,
    required this.cwd,
    this.shell,
    this.env = const {},
    this.maxItems,
    this.sessionId,
  });

  final String buffer;
  final int cursor;
  final String cwd;
  final String? shell;
  final Map<String, String> env;
  final int? maxItems;
  final String? sessionId;

  TerminalCompleteRequest copyWith({
    String? buffer,
    int? cursor,
    String? cwd,
    String? shell,
    Map<String, String>? env,
    int? maxItems,
    String? sessionId,
  }) {
    return TerminalCompleteRequest(
      buffer: buffer ?? this.buffer,
      cursor: cursor ?? this.cursor,
      cwd: cwd ?? this.cwd,
      shell: shell ?? this.shell,
      env: env ?? this.env,
      maxItems: maxItems ?? this.maxItems,
      sessionId: sessionId ?? this.sessionId,
    );
  }

  Map<String, Object?> toJson() => {
    'buffer': buffer,
    'cursor': cursor,
    'cwd': cwd,
    'shell': shell,
    'env': env,
    'max_items': maxItems,
    'session_id': sessionId,
  };
}

class TerminalCompleteResponse {
  const TerminalCompleteResponse({this.suggestion, this.items = const []});

  final String? suggestion;
  final List<TerminalCompletionItem> items;

  factory TerminalCompleteResponse.fromJson(Map<String, Object?> json) {
    final rawItems = json['items'];
    return TerminalCompleteResponse(
      suggestion: json['suggestion']?.toString(),
      items: rawItems is List
          ? rawItems
                .whereType<Map>()
                .map(
                  (item) => TerminalCompletionItem.fromJson(
                    item.cast<String, Object?>(),
                  ),
                )
                .toList(growable: false)
          : const [],
    );
  }
}

class TerminalCompletionItem {
  const TerminalCompletionItem({
    required this.label,
    required this.insertText,
    required this.kind,
    required this.score,
    this.description,
  });

  final String label;
  final String insertText;
  final CompletionKind kind;
  final String? description;
  final int score;

  factory TerminalCompletionItem.fromJson(Map<String, Object?> json) {
    return TerminalCompletionItem(
      label: json['label']?.toString() ?? '',
      insertText: json['insert_text']?.toString() ?? '',
      kind: _completionKindFromJson(json['kind']?.toString()),
      description: json['description']?.toString(),
      score: int.tryParse(json['score']?.toString() ?? '') ?? 0,
    );
  }
}

CompletionKind _completionKindFromJson(String? value) {
  return switch (value) {
    'Command' => CompletionKind.command,
    'Path' => CompletionKind.path,
    'Directory' => CompletionKind.directory,
    'File' => CompletionKind.file,
    'Env' => CompletionKind.env,
    'Git' => CompletionKind.git,
    'History' => CompletionKind.history,
    _ => CompletionKind.command,
  };
}
