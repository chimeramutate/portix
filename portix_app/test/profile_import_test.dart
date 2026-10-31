import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/features/ssh_profiles/controller/profile_file_controller.dart';

void main() {
  test('an imported profile never turns agent forwarding on', () async {
    final dir = await Directory.systemTemp.createTemp('portix-import');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/profile.json')
      ..writeAsStringSync(
        jsonEncode({
          'schema': 'portix.ssh_profiles',
          'version': 1,
          'profiles': [
            {
              'id': 'p1',
              'name': 'box',
              'host': 'example.test',
              'port': 22,
              'username': 'me',
              'forwardAgent': true,
            },
          ],
        }),
      );

    final profiles = await const ProfileFileController().importProfiles(
      file.path,
    );

    expect(profiles.single.name, 'box');
    expect(profiles.single.forwardAgent, isFalse);
  });
}
