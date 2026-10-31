import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/domain/entities/ssh/ssh_profile.dart';
import 'package:portix/src/features/sftp/window/sftp_window_arguments.dart';

const _profile = SshProfile(
  id: 'p1',
  name: 'cluster',
  host: 'example.test',
  port: 22,
  username: 'me',
  group: '',
  tags: [],
  authMethod: AuthMethod.sshKey,
  credentialLabel: '',
  defaultPath: '~',
  status: ConnectionStatus.offline,
  color: ProfileColor.cyan,
);

void main() {
  test('off by default and kept by copyWith', () {
    expect(_profile.runsKubernetes, isFalse);
    final on = _profile.copyWith(runsKubernetes: true);
    expect(on.copyWith(name: 'renamed').runsKubernetes, isTrue);
    expect(on, isNot(_profile));
  });

  test('survives the hand-off to an SFTP window', () {
    final args = SftpWindowArguments(
      profile: _profile.copyWith(runsKubernetes: true),
      remotePath: '~',
    );
    final copy = SftpWindowArguments.fromJsonString(jsonEncode(args.toJson()));
    expect(copy.profile.runsKubernetes, isTrue);
  });
}
