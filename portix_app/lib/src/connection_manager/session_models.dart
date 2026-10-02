enum ConnectionStatus { disconnected, connecting, connected, error }

/// An active local port forward: 127.0.0.1:[localPort] reaches
/// [remoteHost]:[remotePort] as seen from the SSH server.
class PortForward {
  const PortForward({
    required this.id,
    required this.profileId,
    required this.localPort,
    required this.remoteHost,
    required this.remotePort,
  });

  final String id;
  final String profileId;
  final int localPort;
  final String remoteHost;
  final int remotePort;
}

/// A server host key the backend refused during the last connect.
class HostKeyInfo {
  const HostKeyInfo({
    required this.algorithm,
    required this.fingerprint,
    this.changedLine,
  });

  final String algorithm;

  /// SHA-256 fingerprint, same format as `ssh-keygen -l`.
  final String fingerprint;

  /// known_hosts line of the previously recorded key, when the key *changed*.
  final int? changedLine;

  bool get changed => changedLine != null;
}

class TerminalSession {
  const TerminalSession({
    required this.id,
    required this.profileId,
    required this.title,
    required this.status,
  });

  final String id;
  final String profileId;
  final String title;
  final ConnectionStatus status;

  String get remoteSessionId => id;

  TerminalSession copyWith({ConnectionStatus? status, String? title}) {
    return TerminalSession(
      id: id,
      profileId: profileId,
      title: title ?? this.title,
      status: status ?? this.status,
    );
  }
}

class TerminalOutputEvent {
  const TerminalOutputEvent({required this.sessionId, required this.data});

  final String sessionId;
  final String data;
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

/// Which passphrase problem a connect failure reports, matched on the Rust
/// `PortixError` messages (`KeyPassphraseRequired` / `KeyPassphraseIncorrect`).
enum KeyPassphraseProblem { required, incorrect }

KeyPassphraseProblem? keyPassphraseProblemOf(Object error) {
  final message = '$error';
  if (message.contains('a passphrase is required')) {
    return KeyPassphraseProblem.required;
  }
  if (message.contains('wrong passphrase for SSH key')) {
    return KeyPassphraseProblem.incorrect;
  }
  return null;
}
