import 'dart:io';

import 'package:portix/src/domain/entities/sftp/index.dart';

class LocalDirectoryResult {
  const LocalDirectoryResult({required this.path, required this.entries});

  final String path;
  final List<SftpFileEntry> entries;
}

class LocalFileBrowser {
  String defaultPath() {
    final home = Platform.environment['HOME'];
    if (home != null && home.trim().isNotEmpty) return home;
    final userProfile = Platform.environment['USERPROFILE'];
    if (userProfile != null && userProfile.trim().isNotEmpty) {
      return userProfile;
    }
    return Directory.current.path;
  }

  String defaultDownloadsPath() {
    final home = Platform.environment['HOME'];
    if (home != null && home.trim().isNotEmpty) {
      return '$home${Platform.pathSeparator}Downloads';
    }
    final userProfile = Platform.environment['USERPROFILE'];
    if (userProfile != null && userProfile.trim().isNotEmpty) {
      return '$userProfile${Platform.pathSeparator}Downloads';
    }
    return Directory.current.path;
  }

  Future<LocalDirectoryResult> readDirectory(String path) async {
    final normalized = path.trim().isEmpty ? defaultPath() : path.trim();
    final directory = Directory(normalized);
    if (!await directory.exists()) {
      throw FileSystemException('Local folder not found', normalized);
    }

    final entries = <SftpFileEntry>[];
    final parent = directory.parent.path;
    if (parent != directory.path) {
      entries.add(
        SftpFileEntry(
          name: '..',
          path: parent,
          size: '-',
          modified: '-',
          folder: true,
        ),
      );
    }

    await for (final entity in directory.list(followLinks: false)) {
      final stat = await entity.stat();
      final isDirectory = stat.type == FileSystemEntityType.directory;
      entries.add(
        SftpFileEntry(
          name: _basename(entity.path),
          path: entity.path,
          size: isDirectory ? '-' : _formatFileSize(stat.size),
          modified: _formatDate(stat.modified),
          type: isDirectory ? 'dir' : 'file',
          folder: isDirectory,
        ),
      );
    }

    entries.sort((a, b) {
      if (a.name == '..') return -1;
      if (b.name == '..') return 1;
      if (a.folder != b.folder) return a.folder ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    return LocalDirectoryResult(path: directory.path, entries: entries);
  }
}

String _basename(String path) {
  final normalized = path.replaceAll('\\', '/');
  final parts = normalized.split('/')..removeWhere((part) => part.isEmpty);
  return parts.isEmpty ? normalized : parts.last;
}

String _formatFileSize(int bytes) {
  if (bytes <= 0) return '-';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var size = bytes.toDouble();
  var unitIndex = 0;
  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024;
    unitIndex += 1;
  }
  final value = size >= 10 || unitIndex == 0
      ? size.toStringAsFixed(0)
      : size.toStringAsFixed(1);
  return '$value ${units[unitIndex]}';
}

String _formatDate(DateTime date) {
  final now = DateTime.now();
  String two(int value) => value.toString().padLeft(2, '0');
  if (date.year == now.year && date.month == now.month && date.day == now.day) {
    return 'Today ${two(date.hour)}:${two(date.minute)}';
  }
  final yesterday = DateTime(
    now.year,
    now.month,
    now.day,
  ).subtract(const Duration(days: 1));
  if (date.year == yesterday.year &&
      date.month == yesterday.month &&
      date.day == yesterday.day) {
    return 'Yesterday';
  }
  return '${date.year}-${two(date.month)}-${two(date.day)}';
}
