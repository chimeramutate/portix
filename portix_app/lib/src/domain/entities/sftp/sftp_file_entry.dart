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
  });

  final String name;
  final String? path;
  final String? location;
  final String size;
  final String modified;
  final String type;
  final bool folder;
  final String? chmodMode;
}
