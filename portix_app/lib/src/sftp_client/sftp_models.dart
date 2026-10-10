class RemoteFileEntry {
  const RemoteFileEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.sizeBytes,
    this.modifiedUnixSeconds = 0,
    this.mode = 0,
  });

  final String name;
  final String path;
  final bool isDirectory;
  final int sizeBytes;
  final int modifiedUnixSeconds;

  /// Permission bits (e.g. 0x1ED for 0755); 0 when the server did not say.
  final int mode;
}

/// Bytes moved so far out of [total]; a resumed transfer starts above 0.
class TransferProgress {
  const TransferProgress(this.done, this.total);

  final int done;
  final int total;

  double get fraction => total == 0 ? 1 : done / total;
}

enum SftpStatus { connected, disconnected }

class SftpSession {
  const SftpSession({
    required this.id,
    required this.profileId,
    this.status = SftpStatus.connected,
  });

  final String id;
  final String profileId;
  final SftpStatus status;

  bool get isConnected => status == SftpStatus.connected;
}
