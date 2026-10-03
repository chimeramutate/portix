import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/connection_manager/profile_secret_store.dart';

void main() {
  test(
    'passwords survive security -i quoting (temporary keychain)',
    () async {
      final dir = await Directory.systemTemp.createTemp('portix-kc');
      final keychain = '${dir.path}/test.keychain';
      await Process.run('security', ['create-keychain', '-p', 'x', keychain]);
      addTearDown(() async {
        await Process.run('security', ['delete-keychain', keychain]);
        await dir.delete(recursive: true);
      });

      for (final password in [
        'simple',
        'sp ace',
        'q"uote',
        r'back\slash',
        r'd$ollar!%^&*()',
        'Drfv\\"\\',
      ]) {
        final process = await Process.start('security', ['-i']);
        process.stdin.writeln(
          macKeychainAddCommand('svc', 'acct', password, keychain: keychain),
        );
        await process.stdin.close();
        await process.exitCode;
        final read = await Process.run('security', [
          'find-generic-password',
          '-w',
          '-s',
          'svc',
          '-a',
          'acct',
          keychain,
        ]);
        expect(
          (read.stdout as String).replaceFirst(RegExp(r'\n$'), ''),
          password,
        );
      }
    },
    skip: !Platform.isMacOS,
  );
}
