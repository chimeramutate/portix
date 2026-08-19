import 'package:equatable/equatable.dart';

/// Represents an RDP connection profile, supporting both manually configured
/// and CyberArk PSM-sourced connections (parsed from .rdp files).
class RdpProfile extends Equatable {
  const RdpProfile({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    required this.username,
    required this.group,
    required this.tags,
    required this.color,
    this.password,
    this.domain,
    this.desktopWidth = 1280,
    this.desktopHeight = 800,
    this.fullScreen = false,
    this.redirectDrives = false,
    this.redirectClipboard = true,
    this.alternateShell = '',
    this.enableCredSsp = false,
    this.sourceRdpFilePath,
    this.status = RdpProfileStatus.offline,
    this.lastUsedLabel = 'never',
    this.localSharePath,
    this.localShareName = defaultLocalShareName,
  });

  static const String defaultLocalShareName = 'PORTIX';

  /// Default local folder exposed to the remote session.
  /// An empty `/`-style tilde resolves to the user's home directory
  /// (see RdpBackendService._expandLocalSharePath).
  static const String defaultLocalSharePath = '~';

  final String id;
  final String name;
  final String host;
  final int port;
  final String username;
  final String? password;
  final String? domain;
  final String group;
  final List<String> tags;
  final RdpProfileColor color;

  // Display settings
  final int desktopWidth;
  final int desktopHeight;
  final bool fullScreen;

  // Redirect settings
  final bool redirectDrives;
  final bool redirectClipboard;

  final String? localSharePath;
  final String localShareName;

  String get effectiveLocalSharePath {
    final path = localSharePath?.trim();
    return path == null || path.isEmpty ? defaultLocalSharePath : path;
  }

  String get effectiveLocalShareName {
    final name = localShareName.trim();
    return name.isEmpty ? defaultLocalShareName : name;
  }

  // CyberArk PSM fields
  final String alternateShell;
  final bool enableCredSsp;

  // Source .rdp file path (if imported from file)
  final String? sourceRdpFilePath;

  final RdpProfileStatus status;
  final String lastUsedLabel;

  String get address => host.isEmpty ? 'Not configured' : '$host:$port';

  bool get isConnectable => host.isNotEmpty;

  /// True if this profile came from a CyberArk PSM .rdp file.
  bool get isCyberArkPsm => alternateShell.toLowerCase().contains('psm');

  RdpProfile copyWith({
    String? id,
    String? name,
    String? host,
    int? port,
    String? username,
    String? password,
    bool clearPassword = false,
    String? domain,
    String? group,
    List<String>? tags,
    RdpProfileColor? color,
    int? desktopWidth,
    int? desktopHeight,
    bool? fullScreen,
    bool? redirectDrives,
    bool? redirectClipboard,
    String? alternateShell,
    bool? enableCredSsp,
    String? sourceRdpFilePath,
    bool clearSourceRdpFilePath = false,
    RdpProfileStatus? status,
    String? lastUsedLabel,
    String? localSharePath,
    bool clearLocalSharePath = false,
    String? localShareName,
  }) {
    return RdpProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      password: clearPassword ? null : password ?? this.password,
      domain: domain ?? this.domain,
      group: group ?? this.group,
      tags: tags ?? this.tags,
      color: color ?? this.color,
      desktopWidth: desktopWidth ?? this.desktopWidth,
      desktopHeight: desktopHeight ?? this.desktopHeight,
      fullScreen: fullScreen ?? this.fullScreen,
      redirectDrives: redirectDrives ?? this.redirectDrives,
      redirectClipboard: redirectClipboard ?? this.redirectClipboard,
      alternateShell: alternateShell ?? this.alternateShell,
      enableCredSsp: enableCredSsp ?? this.enableCredSsp,
      sourceRdpFilePath: clearSourceRdpFilePath
          ? null
          : sourceRdpFilePath ?? this.sourceRdpFilePath,
      status: status ?? this.status,
      lastUsedLabel: lastUsedLabel ?? this.lastUsedLabel,
      localSharePath: clearLocalSharePath
          ? null
          : localSharePath ?? this.localSharePath,
      localShareName: localShareName ?? this.localShareName,
    );
  }

  @override
  List<Object?> get props => [
    id,
    name,
    host,
    port,
    username,
    domain,
    group,
    tags,
    color,
    desktopWidth,
    desktopHeight,
    fullScreen,
    redirectDrives,
    redirectClipboard,
    alternateShell,
    enableCredSsp,
    sourceRdpFilePath,
    status,
    lastUsedLabel,
    localSharePath,
    localShareName,
  ];
}

enum RdpProfileStatus { offline, connecting, connected, error, draft }

enum RdpProfileColor { blue, cyan, green, amber, pink }
