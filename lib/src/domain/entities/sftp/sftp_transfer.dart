import 'sftp_file_entry.dart';

class SftpFileTransfer {
  const SftpFileTransfer({
    required this.file,
    required this.fromRemote,
    this.files = const [],
  });

  final SftpFileEntry file;
  final List<SftpFileEntry> files;
  final bool fromRemote;

  List<SftpFileEntry> get entries => files.isEmpty ? [file] : files;
}

class SftpTransferJob {
  const SftpTransferJob({
    required this.id,
    required this.name,
    required this.direction,
    required this.value,
    this.queued = false,
    this.done = false,
    this.failed = false,
    this.error,
  });

  final int id;
  final String name;
  final String direction;
  final double value;
  final bool queued;
  final bool done;
  final bool failed;
  final String? error;

  SftpTransferJob copyWith({
    double? value,
    bool? queued,
    bool? done,
    bool? failed,
    String? error,
  }) {
    return SftpTransferJob(
      id: id,
      name: name,
      direction: direction,
      value: value ?? this.value,
      queued: queued ?? this.queued,
      done: done ?? this.done,
      failed: failed ?? this.failed,
      error: error ?? this.error,
    );
  }
}
