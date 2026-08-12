import 'dart:convert';

class RdpWindowArguments {
  const RdpWindowArguments({
    required this.sessionId,
    required this.profileId,
    required this.profileName,
    required this.host,
    required this.port,
    required this.desktopWidth,
    required this.desktopHeight,
  });

  final String sessionId;
  final String profileId;
  final String profileName;
  final String host;
  final int port;
  final int desktopWidth;
  final int desktopHeight;

  factory RdpWindowArguments.fromJsonString(String value) {
    final map = jsonDecode(value) as Map<String, dynamic>;

    if (map['type'] != 'portix_rdp_session') {
      throw const FormatException('Unsupported Portix window type');
    }

    return RdpWindowArguments(
      sessionId: map['sessionId'] as String,
      profileId: map['profileId'] as String,
      profileName: map['profileName'] as String? ?? 'RDP Session',
      host: map['host'] as String? ?? '',
      port: (map['port'] as num?)?.toInt() ?? 3389,
      desktopWidth: (map['desktopWidth'] as num?)?.toInt() ?? 1280,
      desktopHeight: (map['desktopHeight'] as num?)?.toInt() ?? 800,
    );
  }
}
