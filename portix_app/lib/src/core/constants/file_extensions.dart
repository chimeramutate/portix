/// File extensions recognized as source code / config files.
/// Used to decide whether to open with a code editor vs system default.
const Set<String> kCodeFileExtensions = {
  'astro',
  'bash',
  'bat',
  'c',
  'cc',
  'conf',
  'cpp',
  'cs',
  'css',
  'dart',
  'env',
  'go',
  'gradle',
  'h',
  'hpp',
  'html',
  'java',
  'js',
  'json',
  'jsx',
  'kt',
  'kts',
  'lua',
  'm',
  'md',
  'php',
  'plist',
  'py',
  'rb',
  'rs',
  'scss',
  'sh',
  'sql',
  'swift',
  'toml',
  'ts',
  'tsx',
  'txt',
  'vue',
  'xml',
  'yaml',
  'yml',
  'zsh',
};

/// File names (without extension) that should be treated as code files.
const Set<String> kCodeFileNames = {
  'dockerfile',
  'makefile',
  'gemfile',
  'rakefile',
  'procfile',
  'license',
  'readme',
};

/// Returns the file extension (lowercase, without dot) from a file name.
String fileExtension(String fileName) {
  final index = fileName.lastIndexOf('.');
  if (index < 0 || index == fileName.length - 1) return '';
  return fileName.substring(index + 1).toLowerCase();
}

/// Whether [fileName] opens in a code editor by default: a known extension,
/// a dotfile, or a name like `Dockerfile`.
bool isCodeFileName(String fileName) {
  final extension = fileExtension(fileName);
  if (extension.isEmpty) {
    return fileName.startsWith('.') ||
        kCodeFileNames.contains(fileName.toLowerCase());
  }
  return kCodeFileExtensions.contains(extension);
}
