import 'package:portix/src/domain/entities/ssh/index.dart' as domain;

typedef QuickConnectTarget = ({String user, String host, int port});

final _quickConnect = RegExp(
  // [ssh] [user@](host | [ipv6])[:port] [-p port]
  r'^(?:ssh\s+)?(?:([^@\s]+)@)?(\[[0-9a-fA-F:.]+\]|[A-Za-z0-9._-]+)'
  r'(?::(\d{1,5}))?(?:\s+-p\s*(\d{1,5}))?$',
);

/// Parses what someone would type after `ssh`: `host`, `user@host`,
/// `user@host:2222`, `ssh user@host -p 2222`, `user@[::1]:22`. Without a
/// user, [defaultUser] is used, like OpenSSH does with the local login.
/// Null when [input] is not an address (e.g. a profile search word).
QuickConnectTarget? parseQuickConnect(
  String input, {
  required String defaultUser,
}) {
  final match = _quickConnect.firstMatch(input.trim());
  if (match == null) return null;
  var host = match.group(2)!;
  // A bare word is more likely a profile search than a host name.
  final looksLikeHost =
      host.contains('.') ||
      host.startsWith('[') ||
      host == 'localhost' ||
      match.group(1) != null;
  if (!looksLikeHost) return null;
  if (host.startsWith('[')) host = host.substring(1, host.length - 1);
  final port = int.parse(match.group(4) ?? match.group(3) ?? '22');
  if (port < 1 || port > 65535) return null;
  return (user: match.group(1) ?? defaultUser, host: host, port: port);
}

String quickConnectLabel(QuickConnectTarget target) {
  final host = target.host.contains(':') ? '[${target.host}]' : target.host;
  final port = target.port == 22 ? '' : ':${target.port}';
  return '${target.user}@$host$port';
}

/// The saved profile behind a quick connect: password login, asked for on
/// the first connect and kept in the keychain like any password profile.
domain.SshProfile quickConnectProfile(QuickConnectTarget target) {
  final label = quickConnectLabel(target);
  return domain.SshProfile(
    id: 'quick-$label',
    name: label,
    host: target.host,
    port: target.port,
    username: target.user,
    group: 'Quick connect',
    tags: const [],
    authMethod: domain.AuthMethod.password,
    credentialLabel: '',
    defaultPath: '~',
    status: domain.ConnectionStatus.offline,
    color: domain.ProfileColor.cyan,
  );
}
