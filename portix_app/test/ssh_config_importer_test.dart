import 'package:flutter_test/flutter_test.dart';
import 'package:portix/src/domain/entities/ssh/index.dart';
import 'package:portix/src/features/ssh_profiles/controller/ssh_config_importer.dart';

const _config = '''
# personal servers
Host web prod-api
    HostName 10.0.0.5
    User deploy
    IdentityFile ~/.ssh/work_ed25519

Host prod-api
    Port 2200
    User ignored-because-web-block-came-first

Host db.internal
    Port=5022

Host bastion-*
    User jump

Host *.internal !secret.internal
    IdentityFile "%d/.ssh/%h_key"

Host *
    User fallback
    Port 22
''';

List<SshProfile> _parse({Set<String> existing = const {}}) => parseSshConfig(
  _config,
  home: '/home/me',
  defaultUser: 'me',
  fileExists: existing.contains,
);

void main() {
  test('one profile per concrete alias; patterns only provide defaults', () {
    expect(_parse().map((p) => p.name), ['web', 'prod-api', 'db.internal']);
  });

  test('first matching value wins, across blocks in file order', () {
    final api = _parse().singleWhere((p) => p.name == 'prod-api');
    expect(api.host, '10.0.0.5');
    expect(api.username, 'deploy');
    expect(api.port, 2200, reason: 'web block sets no Port, so the next wins');
    expect(api.authMethod, AuthMethod.sshKey);
    expect(api.credentialLabel, '/home/me/.ssh/work_ed25519');
  });

  test('wildcard defaults, key=value syntax, quotes and %tokens', () {
    final db = _parse().singleWhere((p) => p.name == 'db.internal');
    expect(db.host, 'db.internal');
    expect(db.port, 5022);
    expect(db.username, 'fallback');
    expect(db.credentialLabel, '/home/me/.ssh/db.internal_key');
  });

  test('falls back to a default key, then to ssh-agent', () {
    const config = 'Host a\n  HostName a.example\n';
    final withKey = parseSshConfig(
      config,
      home: '/h',
      defaultUser: 'me',
      fileExists: (path) => path == '/h/.ssh/id_rsa',
    ).single;
    expect(withKey.credentialLabel, '/h/.ssh/id_rsa');
    expect(withKey.username, 'me');

    final noKey = parseSshConfig(
      config,
      home: '/h',
      defaultUser: 'me',
      fileExists: (_) => false,
    ).single;
    expect(noKey.authMethod, AuthMethod.sshKey);
    expect(noKey.credentialLabel, isEmpty);
  });

  test('negated pattern excludes a host', () {
    const config = '''
Host secret.internal other.internal
Host *.internal !secret.internal
  User team
''';
    final profiles = parseSshConfig(
      config,
      home: '/h',
      defaultUser: 'me',
      fileExists: (_) => false,
    );
    expect(
      profiles.firstWhere((p) => p.name == 'secret.internal').username,
      'me',
    );
    expect(
      profiles.firstWhere((p) => p.name == 'other.internal').username,
      'team',
    );
  });
}
