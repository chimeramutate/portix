import 'package:flutter/foundation.dart';

import '../domain/entities/ssh/ssh_profile.dart' as domain;

@immutable
class SshProfile {
  const SshProfile({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.username,
    this.password,
    this.hasPassword = false,
    this.privateKeyPath,
    this.group,
    this.tags = const <String>[],
  });

  final String id;
  final String name;
  final String host;
  final int port;
  final String username;
  final String? password;
  final bool hasPassword;
  final String? privateKeyPath;

  final String? group;
  final List<String> tags;

  /// Connection view of a saved profile. The domain stores either the key
  /// path or the password in `credentialLabel`, depending on `authMethod`;
  /// 'Saved password' is a placeholder meaning "read it from the keychain".
  factory SshProfile.fromDomain(domain.SshProfile profile) {
    final credential = profile.credentialLabel.trim();
    final usesPassword = profile.authMethod == domain.AuthMethod.password;
    return SshProfile(
      id: profile.id,
      name: profile.name,
      host: profile.host,
      port: profile.port,
      username: profile.username,
      password:
          usesPassword &&
              credential.isNotEmpty &&
              credential != 'Saved password'
          ? credential
          : null,
      hasPassword: usesPassword,
      privateKeyPath: usesPassword ? null : credential,
      group: profile.group,
      tags: profile.tags,
    );
  }

  SshProfile copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
    String? username,
    String? password,
    bool? hasPassword,
    bool clearPassword = false,
    String? privateKeyPath,
    bool clearPrivateKeyPath = false,
    String? group,
    List<String>? tags,
  }) {
    return SshProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      password: clearPassword ? null : password ?? this.password,
      hasPassword: hasPassword ?? this.hasPassword,
      privateKeyPath: clearPrivateKeyPath
          ? null
          : privateKeyPath ?? this.privateKeyPath,
      group: group ?? this.group,
      tags: tags ?? this.tags,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'name': name,
      'host': host,
      'port': port,
      'username': username,
      'hasPassword': hasPassword,
      'privateKeyPath': privateKeyPath,
      'group': group,
      'tags': tags,
    };
  }

  factory SshProfile.fromJson(Map<String, Object?> json) {
    return SshProfile(
      id: json['id'] as String,
      name: json['name'] as String,
      host: json['host'] as String,
      port: json['port'] as int,
      username: json['username'] as String,
      hasPassword:
          json['hasPassword'] as bool? ??
          ((json['password'] as String?)?.isNotEmpty ?? false),
      privateKeyPath: json['privateKeyPath'] as String?,
      group: json['group'] as String?,

      tags: (json['tags'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}
