import 'dart:convert';

import 'package:portix/src/domain/entities/rdp/index.dart';

class RdpWindowArguments {
  const RdpWindowArguments({
    required this.sessionId,
    required this.profileId,
    required this.profileName,
    required this.host,
    required this.port,
    required this.desktopWidth,
    required this.desktopHeight,
    required this.profile,
  });

  final String sessionId;
  final String profileId;
  final String profileName;
  final String host;
  final int port;
  final int desktopWidth;
  final int desktopHeight;
  final RdpProfile profile;

  factory RdpWindowArguments.fromJsonString(String value) {
    final map = jsonDecode(value) as Map<String, dynamic>;

    if (map['type'] != 'portix_rdp_session') {
      throw const FormatException('Unsupported Portix window type');
    }

    final profileMap = map['profile'] is Map<String, dynamic>
        ? map['profile'] as Map<String, dynamic>
        : null;

    return RdpWindowArguments(
      sessionId: map['sessionId'] as String,
      profileId: map['profileId'] as String,
      profileName: map['profileName'] as String? ?? 'RDP Session',
      host: map['host'] as String? ?? '',
      port: (map['port'] as num?)?.toInt() ?? 3389,
      desktopWidth: (map['desktopWidth'] as num?)?.toInt() ?? 1280,
      desktopHeight: (map['desktopHeight'] as num?)?.toInt() ?? 800,
      profile: _profileFromMap(
        profileMap,
        fallbackSessionId: map['profileId'] as String? ?? '',
        fallbackName: map['profileName'] as String? ?? 'RDP Session',
        fallbackHost: map['host'] as String? ?? '',
        fallbackPort: (map['port'] as num?)?.toInt() ?? 3389,
        fallbackDesktopWidth: (map['desktopWidth'] as num?)?.toInt() ?? 1280,
        fallbackDesktopHeight: (map['desktopHeight'] as num?)?.toInt() ?? 800,
      ),
    );
  }
}

RdpProfile _profileFromMap(
  Map<String, dynamic>? map, {
  required String fallbackSessionId,
  required String fallbackName,
  required String fallbackHost,
  required int fallbackPort,
  required int fallbackDesktopWidth,
  required int fallbackDesktopHeight,
}) {
  if (map == null) {
    return RdpProfile(
      id: fallbackSessionId,
      name: fallbackName,
      host: fallbackHost,
      port: fallbackPort,
      username: '',
      group: 'RDP',
      tags: const [],
      color: RdpProfileColor.blue,
      desktopWidth: fallbackDesktopWidth,
      desktopHeight: fallbackDesktopHeight,
    );
  }

  return RdpProfile(
    id: map['id'] as String? ?? fallbackSessionId,
    name: map['name'] as String? ?? fallbackName,
    host: map['host'] as String? ?? fallbackHost,
    port: (map['port'] as num?)?.toInt() ?? fallbackPort,
    username: map['username'] as String? ?? '',
    password: map['password'] as String?,
    domain: map['domain'] as String?,
    group: map['group'] as String? ?? 'RDP',
    tags: (map['tags'] as List<dynamic>? ?? const [])
        .map((item) => item.toString())
        .toList(),
    color: _enumByName(
      RdpProfileColor.values,
      map['color'] as String?,
      RdpProfileColor.blue,
    ),
    desktopWidth:
        (map['desktopWidth'] as num?)?.toInt() ?? fallbackDesktopWidth,
    desktopHeight:
        (map['desktopHeight'] as num?)?.toInt() ?? fallbackDesktopHeight,
    fullScreen: map['fullScreen'] as bool? ?? false,
    redirectDrives: map['redirectDrives'] as bool? ?? false,
    redirectClipboard: map['redirectClipboard'] as bool? ?? true,
    localSharePath: map['localSharePath'] as String?,
    localShareName:
        map['localShareName'] as String? ?? RdpProfile.defaultLocalShareName,
    alternateShell: map['alternateShell'] as String? ?? '',
    enableCredSsp: map['enableCredSsp'] as bool? ?? false,
    sourceRdpFilePath: map['sourceRdpFilePath'] as String?,
    status: _enumByName(
      RdpProfileStatus.values,
      map['status'] as String?,
      RdpProfileStatus.offline,
    ),
    lastUsedLabel: map['lastUsedLabel'] as String? ?? 'never',
  );
}

T _enumByName<T extends Enum>(List<T> values, String? name, T fallback) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return fallback;
}
