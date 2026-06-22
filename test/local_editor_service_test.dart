import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/data/services/sftp/local_editor_service.dart';

void main() {
  group('LocalEditorService.buildRemoteTempFileName', () {
    test('preserves extension and appends remote path hash plus timestamp', () {
      final fileName = LocalEditorService.buildRemoteTempFileName(
        'config.json',
        remotePath: '/srv/app/config.json',
        now: DateTime.fromMillisecondsSinceEpoch(1712345678901),
      );

      expect(fileName, 'config__41f6b000__1712345678901.json');
    });

    test('same input is deterministic for identical remote path and timestamp', () {
      final now = DateTime.fromMillisecondsSinceEpoch(123456789);
      final first = LocalEditorService.buildRemoteTempFileName(
        'settings.toml',
        remotePath: '/etc/app/settings.toml',
        now: now,
      );
      final second = LocalEditorService.buildRemoteTempFileName(
        'settings.toml',
        remotePath: '/etc/app/settings.toml',
        now: now,
      );

      expect(second, first);
    });

    test('same display name but different remote path yields different names', () {
      final now = DateTime.fromMillisecondsSinceEpoch(5000);
      final first = LocalEditorService.buildRemoteTempFileName(
        'notes.txt',
        remotePath: '/home/a/notes.txt',
        now: now,
      );
      final second = LocalEditorService.buildRemoteTempFileName(
        'notes.txt',
        remotePath: '/home/b/notes.txt',
        now: now,
      );

      expect(first, isNot(second));
      expect(first, startsWith('notes__'));
      expect(second, startsWith('notes__'));
      expect(first, endsWith('.txt'));
      expect(second, endsWith('.txt'));
    });

    test('same remote path but different timestamps yields different names', () {
      final first = LocalEditorService.buildRemoteTempFileName(
        'notes.txt',
        remotePath: '/home/a/notes.txt',
        now: DateTime.fromMillisecondsSinceEpoch(1000),
      );
      final second = LocalEditorService.buildRemoteTempFileName(
        'notes.txt',
        remotePath: '/home/a/notes.txt',
        now: DateTime.fromMillisecondsSinceEpoch(1001),
      );

      expect(first, isNot(second));
      expect(first, contains('__1000'));
      expect(second, contains('__1001'));
    });

    test('sanitizes invalid characters but preserves usable base name', () {
      final fileName = LocalEditorService.buildRemoteTempFileName(
        're:port*2025?.csv',
        remotePath: '/exports/reports/q1.csv',
        now: DateTime.fromMillisecondsSinceEpoch(42),
      );

      expect(fileName, 're_port_2025___134895e8__42.csv');
    });

    test('uses fallback base name when trimmed name becomes empty', () {
      final fileName = LocalEditorService.buildRemoteTempFileName(
        '   ',
        remotePath: '/tmp/demo.txt',
        now: DateTime.fromMillisecondsSinceEpoch(42),
      );

      expect(fileName, 'remote-file__398a8ff9__42');
    });

    test('handles invalid-character-only names without collapsing content', () {
      final fileName = LocalEditorService.buildRemoteTempFileName(
        '  :*?  ',
        remotePath: '/tmp/demo.txt',
        now: DateTime.fromMillisecondsSinceEpoch(42),
      );

      expect(fileName, '_____398a8ff9__42');
    });

    test('keeps dotfiles without treating the leading dot as an extension', () {
      final fileName = LocalEditorService.buildRemoteTempFileName(
        '.env',
        remotePath: '/srv/app/.env',
        now: DateTime.fromMillisecondsSinceEpoch(99),
      );

      expect(fileName, '.env__1bf4ad0f__99');
    });

    test('preserves multi-dot extensions using the last suffix segment', () {
      final fileName = LocalEditorService.buildRemoteTempFileName(
        'archive.tar.gz',
        remotePath: '/backup/archive.tar.gz',
        now: DateTime.fromMillisecondsSinceEpoch(77),
      );

      expect(fileName, 'archive.tar__191a0313__77.gz');
    });

    test('removes path separators and control-invalid characters from display name', () {
      final fileName = LocalEditorService.buildRemoteTempFileName(
        'folder/name\\report<>.log',
        remotePath: '/var/log/report.log',
        now: DateTime.fromMillisecondsSinceEpoch(55),
      );

      expect(fileName, 'folder_name_report____594a56cf__55.log');
      expect(fileName, isNot(contains('/')));
      expect(fileName, isNot(contains(r'\')));
    });
  });
}
