import 'dart:convert';
import 'dart:io';

import 'package:portix/src/core/result/either.dart';
import 'package:portix/src/domain/entities/rdp/index.dart';

class RdpProfileRepository {
  RdpProfileRepository() : _profiles = _loadProfiles();

  final List<RdpProfile> _profiles;
  final _parser = const RdpFileParser();

  // ---------------------------------------------------------------------------
  // Storage
  // ---------------------------------------------------------------------------

  static File get _storeFile {
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.current.path;
    return File('$home${Platform.pathSeparator}.portix/rdp_profiles.json');
  }

  static List<RdpProfile> _loadProfiles() {
    final file = _storeFile;
    if (!file.existsSync()) return [];
    try {
      final source = jsonDecode(file.readAsStringSync());
      if (source is! List) return [];
      return source
          .whereType<Map>()
          .map((item) => _profileFromJson(Map<String, Object?>.from(item)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _persist() async {
    final file = _storeFile;
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(
      encoder.convert(_profiles.map(_profileToJson).toList()),
    );
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  Future<Either<Failure, List<RdpProfile>>> getProfiles() async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
    return Right(List.unmodifiable(_profiles));
  }

  Future<Either<Failure, RdpProfile>> saveProfile(RdpProfile profile) async {
    if (profile.name.trim().isEmpty) {
      return const Left(Failure('Profile name is required.'));
    }
    if (profile.host.trim().isEmpty) {
      return const Left(Failure('Host / IP is required.'));
    }

    final saved = profile.copyWith(status: RdpProfileStatus.offline);
    final index = _profiles.indexWhere((p) => p.id == profile.id);
    if (index == -1) {
      _profiles.insert(0, saved);
    } else {
      _profiles[index] = saved;
    }
    await _persist();
    return Right(saved);
  }

  Future<Either<Failure, Null>> deleteProfile(String id) async {
    _profiles.removeWhere((p) => p.id == id);
    await _persist();
    return const Right(null);
  }

  // ---------------------------------------------------------------------------
  // .rdp file import
  // ---------------------------------------------------------------------------

  /// Import a .rdp file from [filePath] and add it as a new profile.
  Future<Either<Failure, RdpProfile>> importRdpFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return Left(Failure('File not found: $filePath'));
      }
      final content = await file.readAsString();
      final id = 'rdp-${DateTime.now().microsecondsSinceEpoch}';
      final profile = _parser.parse(content, profileId: id, filePath: filePath);
      return saveProfile(profile);
    } catch (error) {
      return Left(Failure('Failed to import .rdp file: $error'));
    }
  }

  /// Export a profile to a temporary .rdp file and return the path.
  Future<Either<Failure, String>> exportToRdpFile(RdpProfile profile) async {
    try {
      final home =
          Platform.environment['HOME'] ??
          Platform.environment['USERPROFILE'] ??
          Directory.current.path;
      final dir = Directory('$home/.portix/rdp_exports');
      await dir.create(recursive: true);

      final safeName = profile.name.replaceAll(RegExp(r'[^\w\s\-]'), '_');
      final path = '${dir.path}/$safeName.rdp';
      await File(path).writeAsString(_parser.serialize(profile));
      return Right(path);
    } catch (error) {
      return Left(Failure('Failed to export .rdp file: $error'));
    }
  }

  // ---------------------------------------------------------------------------
  // JSON serialization
  // ---------------------------------------------------------------------------

  static Map<String, Object?> _profileToJson(RdpProfile p) => {
    'id': p.id,
    'name': p.name,
    'host': p.host,
    'port': p.port,
    'username': p.username,
    'domain': p.domain,
    'group': p.group,
    'tags': p.tags,
    'color': p.color.name,
    'desktopWidth': p.desktopWidth,
    'desktopHeight': p.desktopHeight,
    'fullScreen': p.fullScreen,
    'redirectDrives': p.redirectDrives,
    'redirectClipboard': p.redirectClipboard,
    'alternateShell': p.alternateShell,
    'enableCredSsp': p.enableCredSsp,
    'sourceRdpFilePath': p.sourceRdpFilePath,
    'status': p.status.name,
    'lastUsedLabel': p.lastUsedLabel,
  };

  static RdpProfile _profileFromJson(Map<String, Object?> j) {
    T enumValue<T extends Enum>(List<T> values, Object? v, T fallback) {
      for (final e in values) {
        if (e.name == v) return e;
      }
      return fallback;
    }

    return RdpProfile(
      id: j['id']?.toString() ?? '',
      name: j['name']?.toString() ?? '',
      host: j['host']?.toString() ?? '',
      port: int.tryParse(j['port']?.toString() ?? '') ?? 3389,
      username: j['username']?.toString() ?? '',
      domain: j['domain'] as String?,
      group: j['group']?.toString() ?? 'RDP',
      tags: (j['tags'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      color: enumValue(
        RdpProfileColor.values,
        j['color'],
        RdpProfileColor.blue,
      ),
      desktopWidth: int.tryParse(j['desktopWidth']?.toString() ?? '') ?? 1280,
      desktopHeight: int.tryParse(j['desktopHeight']?.toString() ?? '') ?? 800,
      fullScreen: j['fullScreen'] as bool? ?? false,
      redirectDrives: j['redirectDrives'] as bool? ?? false,
      redirectClipboard: j['redirectClipboard'] as bool? ?? true,
      alternateShell: j['alternateShell']?.toString() ?? '',
      enableCredSsp: j['enableCredSsp'] as bool? ?? false,
      sourceRdpFilePath: j['sourceRdpFilePath'] as String?,
      status: enumValue(
        RdpProfileStatus.values,
        j['status'],
        RdpProfileStatus.offline,
      ),
      lastUsedLabel: j['lastUsedLabel']?.toString() ?? 'never',
    );
  }
}
