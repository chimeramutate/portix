import 'rdp_profile.dart';

/// Parses a Microsoft .rdp file format (including CyberArk PSM exported files)
/// into an [RdpProfile].
///
/// RDP file format: each line is `key:type:value`
/// where type is `s` (string), `i` (integer), or `b` (binary).
///
/// Example CyberArk PSM line:
///   full address:s:172.20.35.10
///   username:s:localhost\PSM@sessionid
///   alternate shell:s:PSM@sessionid
class RdpFileParser {
  const RdpFileParser();

  /// Parse the contents of a .rdp file and return an [RdpProfile].
  /// [filePath] is used to set [RdpProfile.sourceRdpFilePath].
  /// [profileId] is the UUID to assign; generate one before calling.
  RdpProfile parse(
    String content, {
    required String profileId,
    String? filePath,
  }) {
    final settings = _parseLines(content);

    final fullAddress = settings['full address'] ?? '';
    final serverPortStr = settings['server port'];
    final username = settings['username'] ?? '';
    final alternateShell = settings['alternate shell'] ?? '';
    final desktopWidth = int.tryParse(settings['desktopwidth'] ?? '') ?? 1280;
    final desktopHeight = int.tryParse(settings['desktopheight'] ?? '') ?? 800;
    final driveStoreRedirect = settings['drivestoredirect'] ?? '';
    final redirectDrives =
        (int.tryParse(settings['redirectdrives'] ?? '0') ?? 0) == 1 ||
        driveStoreRedirect.trim().isNotEmpty;
    final enableCredSsp =
        (int.tryParse(settings['EnableCredSspSupport'] ?? '0') ?? 0) == 1;
    final screenModeId = int.tryParse(settings['screen mode id'] ?? '1') ?? 1;

    // Parse host and port from full address (may include :port)
    String host;
    int port;
    if (serverPortStr != null) {
      host = fullAddress.trim();
      port = int.tryParse(serverPortStr.trim()) ?? 3389;
    } else {
      final parts = fullAddress.split(':');
      host = parts[0].trim();
      port = parts.length > 1 ? (int.tryParse(parts[1].trim()) ?? 3389) : 3389;
    }

    // Parse domain and username from the username field.
    // CyberArk PSM format: "localhost\PSM@sessionid" or "DOMAIN\user"
    String parsedUsername = username;
    String? parsedDomain;
    if (username.contains('\\')) {
      final parts = username.split('\\');
      parsedDomain = parts[0].trim();
      parsedUsername = parts.sublist(1).join('\\').trim();
    }

    // Derive a friendly name from the file path or host
    final profileName = _deriveName(filePath, host, alternateShell);

    // Detect CyberArk PSM group
    final group = alternateShell.toLowerCase().contains('psm')
        ? 'CyberArk PSM'
        : 'RDP';

    return RdpProfile(
      id: profileId,
      name: profileName,
      host: host,
      port: port,
      username: parsedUsername,
      domain: parsedDomain,
      group: group,
      tags: alternateShell.isNotEmpty ? ['cyberark', 'psm'] : [],
      color: RdpProfileColor.cyan,
      desktopWidth: desktopWidth,
      desktopHeight: desktopHeight,
      fullScreen: screenModeId == 2,
      redirectDrives: redirectDrives,
      redirectClipboard: true,
      localSharePath: redirectDrives ? RdpProfile.defaultLocalSharePath : null,
      alternateShell: alternateShell,
      enableCredSsp: enableCredSsp,
      sourceRdpFilePath: filePath,
      status: RdpProfileStatus.offline,
    );
  }

  /// Serialize an [RdpProfile] back to .rdp file format.
  String serialize(RdpProfile profile) {
    final lines = <String>[
      'full address:s:${profile.host}',
      'server port:i:${profile.port}',
    ];

    final username = profile.domain != null && profile.domain!.isNotEmpty
        ? '${profile.domain}\\${profile.username}'
        : profile.username;

    lines.addAll([
      'username:s:$username',
      if (profile.alternateShell.isNotEmpty)
        'alternate shell:s:${profile.alternateShell}',
      'desktopwidth:i:${profile.desktopWidth}',
      'desktopheight:i:${profile.desktopHeight}',
      'screen mode id:i:${profile.fullScreen ? 2 : 1}',
      'redirectdrives:i:${profile.redirectDrives ? 1 : 0}',
      if (profile.redirectDrives) 'drivestoredirect:s:*',
      'redirectclipboard:i:${profile.redirectClipboard ? 1 : 0}',
      'redirectsmartcards:i:0',
      'EnableCredSspSupport:i:${profile.enableCredSsp ? 1 : 0}',
      'redirectcomports:i:0',
      'remoteapplicationmode:i:0',
      'use multimon:i:0',
      'span monitors:i:0',
    ]);

    return lines.join('\n');
  }

  Map<String, String> _parseLines(String content) {
    final result = <String, String>{};
    for (final line in content.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      // Format: key:type:value  (e.g. "full address:s:192.168.1.1")
      final colonIdx = trimmed.indexOf(':');
      if (colonIdx == -1) continue;

      final key = trimmed.substring(0, colonIdx).trim();
      final rest = trimmed.substring(colonIdx + 1);

      // rest is "type:value" — find second colon
      final typeIdx = rest.indexOf(':');
      if (typeIdx == -1) {
        // No type separator — store raw
        result[key] = rest.trim();
        continue;
      }

      final value = rest.substring(typeIdx + 1).trim();
      result[key] = value;
    }
    return result;
  }

  String _deriveName(String? filePath, String host, String alternateShell) {
    if (filePath != null && filePath.isNotEmpty) {
      // Use the filename without extension, strip UUIDs at the end
      final fileName = filePath.split('/').last.split('\\').last;
      // Remove .rdp extension
      final withoutExt = fileName.endsWith('.rdp')
          ? fileName.substring(0, fileName.length - 4)
          : fileName;
      // Remove trailing UUID pattern like ".97879249-5c68-..."
      final cleanName = withoutExt
          .replaceAll(
            RegExp(
              r'\.[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
              caseSensitive: false,
            ),
            '',
          )
          .trim();
      if (cleanName.isNotEmpty) return cleanName;
    }
    if (alternateShell.isNotEmpty) return alternateShell;
    return host.isEmpty ? 'New RDP' : 'RDP – $host';
  }
}
