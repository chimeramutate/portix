import 'package:flutter/foundation.dart';

/// Represents an RDP connection profile.
@immutable
class RdpProfile {
  const RdpProfile({
    required this.id,
    required this.name,
    required this.host,
    this.port = 3389,
    this.username = '',
    this.password,
    this.hasPassword = false,
    this.domain,
    this.width = 1920,
    this.height = 1080,
    this.screenMode = 1,
    this.group,
    this.tags = const <String>[],
    this.extra = const <String, String>{},
  });

  final String id;
  final String name;
  final String host;
  final int port;
  final String username;
  final String? password;
  final bool hasPassword;
  final String? domain;
  final int width;
  final int height;

  /// Screen mode: 1 = windowed, 2 = fullscreen
  final int screenMode;
  final String? group;
  final List<String> tags;

  /// Additional RDP settings parsed from .rdp file
  final Map<String, String> extra;

  RdpProfile copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
    String? username,
    String? password,
    bool? hasPassword,
    bool clearPassword = false,
    String? domain,
    int? width,
    int? height,
    int? screenMode,
    String? group,
    List<String>? tags,
    Map<String, String>? extra,
  }) {
    return RdpProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      password: clearPassword ? null : password ?? this.password,
      hasPassword: hasPassword ?? this.hasPassword,
      domain: domain ?? this.domain,
      width: width ?? this.width,
      height: height ?? this.height,
      screenMode: screenMode ?? this.screenMode,
      group: group ?? this.group,
      tags: tags ?? this.tags,
      extra: extra ?? this.extra,
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
      'domain': domain,
      'width': width,
      'height': height,
      'screenMode': screenMode,
      'group': group,
      'tags': tags,
      'extra': extra,
    };
  }

  factory RdpProfile.fromJson(Map<String, Object?> json) {
    return RdpProfile(
      id: json['id'] as String,
      name: json['name'] as String,
      host: json['host'] as String,
      port: json['port'] as int? ?? 3389,
      username: json['username'] as String? ?? '',
      hasPassword: json['hasPassword'] as bool? ?? false,
      domain: json['domain'] as String?,
      width: json['width'] as int? ?? 1920,
      height: json['height'] as int? ?? 1080,
      screenMode: json['screenMode'] as int? ?? 1,
      group: json['group'] as String?,
      tags: (json['tags'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      extra: (json['extra'] as Map<String, dynamic>? ?? const {}).map(
        (k, v) => MapEntry(k, v.toString()),
      ),
    );
  }

  /// Parse an .rdp file content into an RdpProfile.
  factory RdpProfile.fromRdpFile({
    required String id,
    required String name,
    required String content,
  }) {
    final settings = <String, String>{};

    for (final line in content.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty ||
          trimmed.startsWith('#') ||
          trimmed.startsWith(';')) {
        continue;
      }

      final parts = trimmed.split(':');
      if (parts.length >= 3) {
        final key = parts[0].trim().toLowerCase();
        final value = parts.sublist(2).join(':').trim();
        settings[key] = value;
      } else if (parts.length == 2) {
        final key = parts[0].trim().toLowerCase();
        final value = parts[1].trim();
        settings[key] = value;
      }
    }

    // Parse host:port from "full address"
    final fullAddress = settings['full address'] ?? '';
    String host;
    int port;

    if (fullAddress.startsWith('[')) {
      // IPv6
      final bracketEnd = fullAddress.indexOf(']');
      host = fullAddress.substring(1, bracketEnd);
      final after = fullAddress.substring(bracketEnd + 1);
      port = after.startsWith(':')
          ? int.tryParse(after.substring(1)) ?? 3389
          : 3389;
    } else if (fullAddress.contains(':')) {
      final lastColon = fullAddress.lastIndexOf(':');
      final potentialPort = int.tryParse(fullAddress.substring(lastColon + 1));
      if (potentialPort != null) {
        host = fullAddress.substring(0, lastColon);
        port = potentialPort;
      } else {
        host = fullAddress;
        port = 3389;
      }
    } else {
      host = fullAddress;
      port = 3389;
    }

    // "port:i:N" overrides port embedded in full address (CyberArk style)
    port = int.tryParse(settings['port'] ?? '') ?? port;

    // Parse "domain\username" (CyberArk PSM format)
    final rawUsername = settings['username'] ?? '';
    String username;
    String? domain;
    final backslash = rawUsername.indexOf('\\');
    if (backslash > 0) {
      domain = rawUsername.substring(0, backslash);
      username = rawUsername.substring(backslash + 1);
    } else {
      username = rawUsername;
      domain = settings['domain'];
    }

    final width = int.tryParse(settings['desktopwidth'] ?? '') ?? 1920;
    final height = int.tryParse(settings['desktopheight'] ?? '') ?? 1080;
    final screenMode = int.tryParse(settings['screen mode id'] ?? '') ?? 1;

    // Remove known keys from extra
    const knownKeys = {
      'full address',
      'port',
      'username',
      'domain',
      'desktopwidth',
      'desktopheight',
      'screen mode id',
    };
    final extra = Map<String, String>.fromEntries(
      settings.entries.where((e) => !knownKeys.contains(e.key)),
    );

    // ── CyberArk PSM normalization ─────────────────────────────────────────
    // CyberArk generates files with both `alternate shell` and
    // `remoteapplicationprogram`. Normalise so that `alternate shell` always
    // wins; fall back to `remoteapplicationprogram` if only that key exists.
    final normalizedExtra = Map<String, String>.from(extra);
    if (!normalizedExtra.containsKey('alternate shell')) {
      final remoteApp = normalizedExtra['remoteapplicationprogram'];
      if (remoteApp != null && remoteApp.isNotEmpty) {
        normalizedExtra['alternate shell'] = remoteApp;
      }
    }

    return RdpProfile(
      id: id,
      name: name,
      host: host,
      port: port,
      username: username,
      domain: domain,
      width: width,
      height: height,
      screenMode: screenMode,
      extra: normalizedExtra,
    );
  }

  /// Generate .rdp file content from this profile.
  String toRdpFileContent() {
    final lines = <String>[];

    final address = port == 3389 ? host : '$host:$port';
    lines.add('full address:s:$address');
    if (username.isNotEmpty) {
      lines.add('username:s:$username');
    }
    if (domain != null && domain!.isNotEmpty) {
      lines.add('domain:s:$domain');
    }
    lines.add('desktopwidth:i:$width');
    lines.add('desktopheight:i:$height');
    lines.add('screen mode id:i:$screenMode');

    for (final entry in extra.entries) {
      lines.add('${entry.key}:s:${entry.value}');
    }

    return lines.join('\r\n');
  }
}
