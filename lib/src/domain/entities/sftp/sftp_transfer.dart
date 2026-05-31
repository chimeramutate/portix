import 'sftp_file_entry.dart';

class SftpFileTransfer {
  const SftpFileTransfer({required this.file, required this.fromRemote});

  final SftpFileEntry file;
  final bool fromRemote;
}

class SftpTransferJob {
  const SftpTransferJob({
    required this.name,
    required this.direction,
    required this.value,
    this.queued = false,
  });

  final String name;
  final String direction;
  final double value;
  final bool queued;
}
