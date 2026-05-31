enum ConnectionStatus { disconnected, connecting, connected, error }

enum SessionKind { ssh, sftp }

enum TerminalColorScheme { portix, matrix, amber, light }

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
