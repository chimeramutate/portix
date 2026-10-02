import 'package:portix/src/domain/entities/ssh/index.dart';

/// Keys OpenSSH tries when a host has no IdentityFile, in its default order.
const defaultIdentityFiles = ['id_ed25519', 'id_ecdsa', 'id_rsa'];

/// Turns an OpenSSH client config into Portix profiles: one per concrete
/// `Host` alias (patterns like `*` or `web-?` only supply defaults).
///
/// Like OpenSSH, the first value found for a keyword wins, across every
/// `Host` block whose patterns match the alias, in file order.
///
/// ponytail: `Include`, `Match` and `ProxyJump` are ignored; add them when
/// someone's config depends on them.
List<SshProfile> parseSshConfig(
  String content, {
  required String home,
  required String defaultUser,
  required bool Function(String path) fileExists,
}) {
  final blocks = <({List<String> patterns, Map<String, String> options})>[];
  for (final rawLine in content.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final match = RegExp(r'^(\S+?)(?:\s*=\s*|\s+)(.+)$').firstMatch(line);
    if (match == null) continue;
    final key = match.group(1)!.toLowerCase();
    final value = _unquote(match.group(2)!.trim());
    if (key == 'host') {
      blocks.add((patterns: value.split(RegExp(r'\s+')), options: {}));
    } else if (key == 'match') {
      // A Match block's options must not leak into the previous Host block.
      blocks.add((patterns: const [], options: {}));
    } else if (blocks.isNotEmpty) {
      blocks.last.options.putIfAbsent(key, () => value);
    }
  }

  final aliases = <String>{
    for (final block in blocks)
      for (final pattern in block.patterns)
        if (!pattern.contains(RegExp(r'[*?!]'))) pattern,
  };

  return [
    for (final alias in aliases)
      _profileFor(
        alias,
        _optionsFor(alias, blocks),
        home: home,
        defaultUser: defaultUser,
        fileExists: fileExists,
      ),
  ];
}

Map<String, String> _optionsFor(
  String alias,
  List<({List<String> patterns, Map<String, String> options})> blocks,
) {
  final options = <String, String>{};
  for (final block in blocks) {
    if (!_hostMatches(alias, block.patterns)) continue;
    block.options.forEach(
      (key, value) => options.putIfAbsent(key, () => value),
    );
  }
  return options;
}

bool _hostMatches(String alias, List<String> patterns) {
  var matched = false;
  for (final pattern in patterns) {
    final negated = pattern.startsWith('!');
    if (!_glob(negated ? pattern.substring(1) : pattern).hasMatch(alias)) {
      continue;
    }
    if (negated) return false;
    matched = true;
  }
  return matched;
}

RegExp _glob(String pattern) => RegExp(
  '^${RegExp.escape(pattern).replaceAll(r'\*', '.*').replaceAll(r'\?', '.')}\$',
  caseSensitive: false,
);

SshProfile _profileFor(
  String alias,
  Map<String, String> options, {
  required String home,
  required String defaultUser,
  required bool Function(String path) fileExists,
}) {
  final host = options['hostname'] ?? alias;
  final user = options['user'] ?? defaultUser;
  String expand(String path) => path
      .replaceAll('%d', home)
      .replaceAll('%h', host)
      .replaceAll('%u', user)
      .replaceFirst(RegExp(r'^~(?=/|$)'), home);

  final identity = switch (options['identityfile']) {
    final path? => expand(path),
    null =>
      defaultIdentityFiles
          .map((name) => '$home/.ssh/$name')
          .where(fileExists)
          .firstOrNull,
  };

  return SshProfile(
    id: 'ssh-config-$alias',
    name: alias,
    host: host,
    port: int.tryParse(options['port'] ?? '') ?? 22,
    username: user,
    group: 'SSH config',
    tags: const [],
    authMethod: identity == null ? AuthMethod.password : AuthMethod.sshKey,
    credentialLabel: identity ?? '',
    defaultPath: '~',
    status: ConnectionStatus.offline,
    color: ProfileColor.cyan,
  );
}

String _unquote(String value) =>
    value.length >= 2 && value.startsWith('"') && value.endsWith('"')
    ? value.substring(1, value.length - 1)
    : value;
