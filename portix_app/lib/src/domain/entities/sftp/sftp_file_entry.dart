class SftpFileEntry {
  const SftpFileEntry({
    required this.name,
    required this.size,
    required this.modified,
    this.path,
    this.location,
    this.type = 'file',
    this.folder = false,
    this.chmodMode,
    this.sizeBytes = 0,
    this.modifiedAt,
  });

  final String name;
  final String? path;
  final String? location;
  final String size;
  final String modified;
  final String type;
  final bool folder;
  final String? chmodMode;

  /// Raw values behind [size] and [modified], for sorting.
  final int sizeBytes;
  final DateTime? modifiedAt;
}
