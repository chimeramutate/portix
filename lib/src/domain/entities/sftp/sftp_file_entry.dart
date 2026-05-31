class SftpFileEntry {
  const SftpFileEntry({
    required this.name,
    required this.size,
    required this.modified,
    this.path,
    this.type = 'file',
    this.folder = false,
  });

  final String name;
  final String? path;
  final String size;
  final String modified;
  final String type;
  final bool folder;
}
