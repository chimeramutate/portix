import 'package:equatable/equatable.dart';

enum AuthMethod { sshKey, password }

enum ConnectionStatus { online, offline, draft, error }

enum ProfileColor { green, cyan, blue, pink, amber }

class SshProfile extends Equatable {
  const SshProfile({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.username,
    required this.group,
    required this.tags,
    required this.authMethod,
    required this.credentialLabel,
    required this.defaultPath,
    required this.status,
    required this.color,
    this.startupCommand = '',
    this.terminalFontSize = 14,
    this.lastUsedLabel = 'recently',
  });

  final String id;
  final String name;
  final String host;
  final int port;
  final String username;
  final String group;
  final List<String> tags;
  final AuthMethod authMethod;
  final String credentialLabel;
  final String defaultPath;
  final ConnectionStatus status;
  final ProfileColor color;
  final String startupCommand;
  final int terminalFontSize;
  final String lastUsedLabel;

  String get address => '$username@$host:$port';
  bool get isConnectable => host.isNotEmpty && username.isNotEmpty;

  SshProfile copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
    String? username,
    String? group,
    List<String>? tags,
    AuthMethod? authMethod,
    String? credentialLabel,
    String? defaultPath,
    ConnectionStatus? status,
    ProfileColor? color,
    String? startupCommand,
    int? terminalFontSize,
    String? lastUsedLabel,
  }) {
    return SshProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      group: group ?? this.group,
      tags: tags ?? this.tags,
      authMethod: authMethod ?? this.authMethod,
      credentialLabel: credentialLabel ?? this.credentialLabel,
      defaultPath: defaultPath ?? this.defaultPath,
      status: status ?? this.status,
      color: color ?? this.color,
      startupCommand: startupCommand ?? this.startupCommand,
      terminalFontSize: terminalFontSize ?? this.terminalFontSize,
      lastUsedLabel: lastUsedLabel ?? this.lastUsedLabel,
    );
  }

  @override
  List<Object?> get props => [
    id,
    name,
    host,
    port,
    username,
    group,
    tags,
    authMethod,
    credentialLabel,
    defaultPath,
    status,
    color,
    startupCommand,
    terminalFontSize,
    lastUsedLabel,
  ];
}
