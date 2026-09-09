import 'dart:convert';

import 'package:portix/src/domain/entities/ssh/index.dart';

/// Parsed arguments for an SFTP session child-window.
///
/// Created on the parent side by [SftpWindowService.openSession] and
/// deserialised on the child-window side by [SftpWindowArguments.fromJsonString].
/// The profile is serialised via the same map format used by
/// [SshProfileRepository] so the two can evolve in lock-step.
class SftpWindowArguments {
  SftpWindowArguments({required this.profile, required this.remotePath});

  final SshProfile profile;

  /// The remote directory the duplicated window should open at.
  final String remotePath;

  factory SftpWindowArguments.fromJsonString(String value) {
    final map = jsonDecode(value) as Map<String, dynamic>;

    if (map['type'] != 'portix_sftp_session') {
      throw const FormatException('Unsupported Portix window type');
    }

    final profileMap = map['profile'];
    if (profileMap is! Map<String, dynamic>) {
      throw const FormatException(
        'Missing profile data in SFTP window arguments',
      );
    }

    return SftpWindowArguments(
      profile: _profileFromMap(profileMap),
      remotePath: map['remotePath']?.toString() ?? '~',
    );
  }

  Map<String, Object?> toJson() {
    return {
      'type': 'portix_sftp_session',
      'profile': _profileToMap(profile),
      'remotePath': remotePath,
    };
  }

  static SshProfile _profileFromMap(Map<String, dynamic> map) {
    T enumValue<T extends Enum>(List<T> values, Object? value, T fallback) {
      for (final item in values) {
        if (item.name == value) return item;
      }
      return fallback;
    }

    return SshProfile(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      host: map['host']?.toString() ?? '',
      port: int.tryParse(map['port']?.toString() ?? '22') ?? 22,
      username: map['username']?.toString() ?? '',
      group: map['group']?.toString() ?? 'Production',
      tags: (map['tags'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
      authMethod: enumValue(
        AuthMethod.values,
        map['authMethod'],
        AuthMethod.sshKey,
      ),
      credentialLabel: map['credentialLabel']?.toString() ?? '',
      defaultPath: map['defaultPath']?.toString() ?? '~',
      status: enumValue(
        ConnectionStatus.values,
        map['status'],
        ConnectionStatus.offline,
      ),
      color: enumValue(ProfileColor.values, map['color'], ProfileColor.green),
      startupCommand: map['startupCommand']?.toString() ?? '',
      terminalFontSize:
          int.tryParse(map['terminalFontSize']?.toString() ?? '14') ?? 14,
      lastUsedLabel: map['lastUsedLabel']?.toString() ?? 'recently',
      osIconAsset: map['osIconAsset']?.toString() ?? '',
    );
  }

  static Map<String, Object?> _profileToMap(SshProfile profile) {
    return {
      'id': profile.id,
      'name': profile.name,
      'host': profile.host,
      'port': profile.port,
      'username': profile.username,
      'group': profile.group,
      'tags': profile.tags,
      'authMethod': profile.authMethod.name,
      'credentialLabel': profile.credentialLabel,
      'defaultPath': profile.defaultPath,
      'status': profile.status.name,
      'color': profile.color.name,
      'startupCommand': profile.startupCommand,
      'terminalFontSize': profile.terminalFontSize,
      'lastUsedLabel': profile.lastUsedLabel,
      'osIconAsset': profile.osIconAsset,
    };
  }
}
