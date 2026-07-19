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

/// Returns true if [fileName] should be opened with a code editor.
bool isCodeFileName(String fileName) {
  final dotIndex = fileName.lastIndexOf('.');
  if (dotIndex < 0 || dotIndex == fileName.length - 1) {
    return fileName.startsWith('.') ||
        kCodeFileNames.contains(fileName.toLowerCase());
  }
  final extension = fileName.substring(dotIndex + 1).toLowerCase();
  return kCodeFileExtensions.contains(extension);
}

/// Returns the file extension (lowercase, without dot) from a file name.
String fileExtension(String fileName) {
  final index = fileName.lastIndexOf('.');
  if (index < 0 || index == fileName.length - 1) return '';
  return fileName.substring(index + 1).toLowerCase();
}
