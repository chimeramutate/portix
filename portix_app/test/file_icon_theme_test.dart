import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/domain/entities/sftp/file_icon_theme.dart';
import 'package:portix/src/domain/entities/sftp/file_type_registry.dart';

void main() {
  String file(String name) =>
      FileTypeRegistry.iconAssetFor(name, folder: false);
  String folder(String name) =>
      FileTypeRegistry.iconAssetFor(name, folder: true);
  String asset(String icon) => 'assets/icons/files/$icon.svg';

  test('files match by name, then longest extension, then default', () {
    expect(file('Dockerfile'), asset('docker'));
    expect(file('README.md'), asset('readme'));
    expect(file('.gitignore'), asset('git'));
    expect(file('index.d.ts'), asset('typescript-def'));
    expect(file('main.py'), asset('python'));
    expect(file('backup.tar.gz'), asset('zip'));
    expect(file('.env'), asset(fileExtensionIcons['env']!));
    expect(file('no-extension'), asset(fileIconDefault));
  });

  test('folders match by name, else the plain folder', () {
    expect(folder('src'), asset('folder-src'));
    expect(folder('.git'), asset('folder-git'));
    expect(folder('node_modules'), asset('folder-node'));
    expect(folder('whatever'), asset(folderIconDefault));
  });

  test('every icon the lookups name is bundled', () {
    final icons = {
      fileIconDefault,
      folderIconDefault,
      ...fileNameIcons.values,
      ...fileExtensionIcons.values,
      ...languageIdIcons.values,
      ...folderNameIcons.values,
    };
    final missing = icons.where((icon) => !File(asset(icon)).existsSync());
    expect(missing, isEmpty);
  });
}
