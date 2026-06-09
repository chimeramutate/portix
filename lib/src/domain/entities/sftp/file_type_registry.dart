/// Maps file extensions to categories and suggested openers.
class FileTypeRegistry {
  const FileTypeRegistry._();

  static FileCategory categoryFor(String fileName) {
    final ext = _extension(fileName).toLowerCase();
    if (ext.isEmpty) {
      if (fileName.startsWith('.')) return FileCategory.code;
      return FileCategory.unknown;
    }
    for (final entry in _categoryMap.entries) {
      if (entry.value.contains(ext)) return entry.key;
    }
    return FileCategory.unknown;
  }

  static String labelFor(FileCategory category) {
    return switch (category) {
      FileCategory.document => 'Document',
      FileCategory.image => 'Image',
      FileCategory.audio => 'Audio',
      FileCategory.video => 'Video',
      FileCategory.archive => 'Archive',
      FileCategory.code => 'Code',
      FileCategory.executable => 'Executable',
      FileCategory.database => 'Database',
      FileCategory.design => 'Design',
      FileCategory.unknown => 'File',
    };
  }

  /// Whether this file type should be opened in a code editor by default.
  static bool isCodeFile(String fileName) {
    final cat = categoryFor(fileName);
    return cat == FileCategory.code;
  }

  /// Whether this file type can be previewed as text.
  static bool isTextViewable(String fileName) {
    final cat = categoryFor(fileName);
    return cat == FileCategory.code || cat == FileCategory.document;
  }

  static String _extension(String fileName) {
    final index = fileName.lastIndexOf('.');
    if (index < 0 || index == fileName.length - 1) return '';
    return fileName.substring(index + 1);
  }

  static const Map<FileCategory, Set<String>> _categoryMap = {
    FileCategory.document: {
      'txt', 'doc', 'docx', 'pdf', 'xls', 'xlsx', 'ppt', 'pptx',
      'csv', 'rtf', 'odt', 'ods', 'odp', 'md', 'pages', 'numbers',
    },
    FileCategory.image: {
      'jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'svg', 'psd',
      'tiff', 'tif', 'ico', 'heic', 'heif', 'raw', 'cr2', 'nef',
    },
    FileCategory.audio: {
      'mp3', 'wav', 'flac', 'aac', 'ogg', 'wma', 'm4a', 'opus', 'aiff',
    },
    FileCategory.video: {
      'mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'webm', 'm4v', 'mpg', 'mpeg',
    },
    FileCategory.archive: {
      'zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz', 'zst', 'lz', 'tgz',
      'tar.gz', 'tar.bz2', 'tar.xz', 'deb', 'rpm', 'dmg', 'iso',
    },
    FileCategory.code: {
      'py', 'js', 'ts', 'jsx', 'tsx', 'html', 'css', 'scss', 'sass',
      'json', 'xml', 'yaml', 'yml', 'java', 'cpp', 'c', 'h', 'hpp',
      'cs', 'go', 'rs', 'rb', 'php', 'swift', 'kt', 'kts', 'dart',
      'lua', 'sh', 'bash', 'zsh', 'fish', 'ps1', 'bat', 'cmd',
      'sql', 'graphql', 'proto', 'toml', 'ini', 'conf', 'env',
      'dockerfile', 'makefile', 'cmake', 'gradle', 'groovy',
      'vue', 'svelte', 'astro', 'elm', 'ex', 'exs', 'erl', 'hs',
      'ml', 'mli', 'clj', 'cljs', 'scala', 'r', 'jl', 'nim', 'zig',
      'tf', 'hcl', 'plist', 'lock', 'mod', 'sum', 'cabal',
    },
    FileCategory.executable: {
      'exe', 'msi', 'apk', 'ipa', 'app', 'deb', 'rpm', 'bin', 'run',
      'appimage', 'snap', 'flatpak',
    },
    FileCategory.database: {
      'db', 'sqlite', 'sqlite3', 'mdb', 'accdb', 'realm',
    },
    FileCategory.design: {
      'ai', 'cdr', 'xd', 'fig', 'sketch', 'blend', 'fbx', 'obj',
      'stl', '3ds', 'dwg', 'dxf',
    },
  };
}

enum FileCategory {
  document,
  image,
  audio,
  video,
  archive,
  code,
  executable,
  database,
  design,
  unknown,
}
