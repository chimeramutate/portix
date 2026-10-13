import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/connection_manager/rust_bridge_backend.dart';
import 'package:portix/src/connection_manager/ssh_profile.dart';
import 'package:portix/src/domain/entities/ssh/ssh_profile.dart' as domain;
import 'package:portix/src/features/sftp/window/sftp_window_arguments.dart';

const _profile = domain.SshProfile(
  id: 'p1',
  name: 'web',
  host: 'example.test',
  port: 22,
  username: 'me',
  group: '',
  tags: [],
  authMethod: domain.AuthMethod.sshKey,
  credentialLabel: '',
  defaultPath: '~',
  status: domain.ConnectionStatus.offline,
  color: domain.ProfileColor.cyan,
  forwardAgent: true,
);

void main() {
  test('off by default', () {
    expect(
      toRustProfile(
        SshProfile.fromDomain(_profile.copyWith(forwardAgent: false)),
      ).forwardAgent,
      isFalse,
    );
  });

  test('reaches the Rust profile, also after credentials are resolved', () {
    final profile = SshProfile.fromDomain(_profile);
    expect(toRustProfile(profile).forwardAgent, isTrue);
    expect(toRustProfile(profile.copyWith(password: 'x')).forwardAgent, isTrue);
  });

  test('survives the hand-off to an SFTP window', () {
    final args = SftpWindowArguments(profile: _profile, remotePath: '~');
    final copy = SftpWindowArguments.fromJsonString(jsonEncode(args.toJson()));
    expect(copy.profile.forwardAgent, isTrue);
  });
}
