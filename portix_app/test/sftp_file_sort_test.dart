import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/domain/entities/sftp/index.dart';
import 'package:portix/src/features/sftp/page/sftp_workspace_page.dart';

SftpFileEntry _file(String name, int size, int day, {bool folder = false}) =>
    SftpFileEntry(
      name: name,
      size: '',
      modified: '',
      folder: folder,
      sizeBytes: size,
      modifiedAt: DateTime(2026, 1, day),
    );

void main() {
  final entries = [
    _file('b.txt', 30, 2),
    _file('src', 0, 9, folder: true),
    _file('A.txt', 10, 5),
    _file('..', 0, 1, folder: true),
    _file('c.txt', 20, 1),
  ];

  List<String> names(FileSortColumn column, bool ascending) => [
    for (final e in sortFileEntries(entries, (
      column: column,
      ascending: ascending,
    )))
      e.name,
  ];

  test('keeps .. and folders first in every order', () {
    expect(names(FileSortColumn.name, true), [
      '..',
      'src',
      'A.txt',
      'b.txt',
      'c.txt',
    ]);
    expect(names(FileSortColumn.name, false), [
      '..',
      'src',
      'c.txt',
      'b.txt',
      'A.txt',
    ]);
  });

  test('sorts by size and by modified time', () {
    expect(names(FileSortColumn.size, false).skip(2), [
      'b.txt',
      'c.txt',
      'A.txt',
    ]);
    expect(names(FileSortColumn.modified, true).skip(2), [
      'c.txt',
      'b.txt',
      'A.txt',
    ]);
  });
}
