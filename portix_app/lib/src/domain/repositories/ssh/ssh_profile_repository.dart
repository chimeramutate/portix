import 'dart:convert';
import 'dart:io';

import 'package:portix/src/connection_manager/profile_secret_store.dart';
import 'package:portix/src/core/result/either.dart';
import 'package:portix/src/domain/entities/ssh/index.dart';

class SshProfileRepository {
  SshProfileRepository({
    ProfileSecretStore secretStore = const ProfileSecretStore(),
  }) : _secretStore = secretStore,
       _profiles = _loadProfiles();

  final ProfileSecretStore _secretStore;
  final List<SshProfile> _profiles;

  static File get _storeFile {
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.current.path;
    return File('$home${Platform.pathSeparator}.portix/profiles.json');
  }

  static List<SshProfile> _loadProfiles() {
    final file = _storeFile;
    if (!file.existsSync()) return [];
    try {
      final source = jsonDecode(file.readAsStringSync());
      if (source is! List) return [];
      return _dedupeProfileIds(
        source
            .whereType<Map>()
            .map((item) => _profileFromJson(Map<String, Object?>.from(item)))
            .toList(),
      );
    } catch (_) {
      return [];
    }
  }

  static List<SshProfile> _dedupeProfileIds(List<SshProfile> profiles) {
    final usedIds = <String>{};
    return [
      for (var index = 0; index < profiles.length; index += 1)
        profiles[index].copyWith(
          id: _uniqueProfileId(profiles[index].id, usedIds, index),
        ),
    ];
  }

  static String _uniqueProfileId(
    String candidate,
    Set<String> usedIds,
    int index,
  ) {
    final normalized = candidate.trim();
    if (normalized.isNotEmpty && !usedIds.contains(normalized)) {
      usedIds.add(normalized);
      return normalized;
    }
    final generated = 'profile-${DateTime.now().microsecondsSinceEpoch}-$index';
    usedIds.add(generated);
    return generated;
  }

  Future<void> _persistProfiles() async {
    final file = _storeFile;
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(
      encoder.convert(_profiles.map(_profileToJson).toList()),
    );
  }

  Future<Either<Failure, List<SshProfile>>> getProfiles() async {
    await Future<void>.delayed(const Duration(milliseconds: 160));
    return Right(List.unmodifiable(_profiles));
  }

  Future<String?> readPasswordForEdit(String profileId) async {
    return _secretStore.readPassword(profileId);
  }

  Future<Either<Failure, SshProfile>> saveProfile(SshProfile profile) async {
    await Future<void>.delayed(const Duration(milliseconds: 220));
    if (profile.name.trim().isEmpty || profile.host.trim().isEmpty) {
      return const Left(Failure('Profile name and host are required.'));
    }

    if (profile.authMethod == AuthMethod.password) {
      final password = profile.credentialLabel.trim();
      if (password.isNotEmpty && password != _kSavedPasswordPlaceholder) {
        await _secretStore.savePassword(profile.id, password);
      }
      profile = profile.copyWith(credentialLabel: _kSavedPasswordPlaceholder);
    } else {
      await _secretStore.deletePassword(profile.id);
    }

    final index = _profiles.indexWhere((item) => item.id == profile.id);
    final saved = profile.copyWith(status: ConnectionStatus.offline);
    if (index == -1) {
      _profiles.insert(0, saved);
    } else {
      _profiles[index] = saved;
    }
    await _persistProfiles();
    return Right(saved);
  }

  static const String _kSavedPasswordPlaceholder = 'Saved password';

  Future<Either<Failure, SshProfile>> testConnection(SshProfile profile) async {
    if (!profile.isConnectable || profile.host.contains('Add host')) {
      return const Left(Failure('Host, port, and username must be valid.'));
    }
    return const Left(
      Failure('Use Open SSH Session to test a real Rust backend connection.'),
    );
  }

  Future<Either<Failure, SshProfile>> connect(SshProfile profile) async {
    if (!profile.isConnectable || profile.status == ConnectionStatus.draft) {
      return const Left(Failure('Complete the profile before opening SSH.'));
    }
    return Right(profile.copyWith(status: ConnectionStatus.offline));
  }

  Future<Either<Failure, Null>> deleteProfile(String id) async {
    await Future<void>.delayed(const Duration(milliseconds: 160));
    _profiles.removeWhere((profile) => profile.id == id);
    await _persistProfiles();
    return const Right(null);
  }

  static Map<String, Object?> _profileToJson(SshProfile profile) {
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

  static SshProfile _profileFromJson(Map<String, Object?> json) {
    T enumValue<T extends Enum>(List<T> values, Object? value, T fallback) {
      for (final item in values) {
        if (item.name == value) return item;
      }
      return fallback;
    }

    return SshProfile(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      host: json['host']?.toString() ?? '',
      port: int.tryParse(json['port']?.toString() ?? '') ?? 22,
      username: json['username']?.toString() ?? '',
      group: json['group']?.toString() ?? 'Production',
      tags: (json['tags'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(),
      authMethod: enumValue(
        AuthMethod.values,
        json['authMethod'],
        AuthMethod.sshKey,
      ),
      credentialLabel: json['credentialLabel']?.toString() ?? '',
      defaultPath: json['defaultPath']?.toString() ?? '~',
      status: enumValue(
        ConnectionStatus.values,
        json['status'],
        ConnectionStatus.offline,
      ),
      color: enumValue(ProfileColor.values, json['color'], ProfileColor.green),
      startupCommand: json['startupCommand']?.toString() ?? '',
      terminalFontSize:
          int.tryParse(json['terminalFontSize']?.toString() ?? '') ?? 14,
      lastUsedLabel: json['lastUsedLabel']?.toString() ?? 'recently',
      osIconAsset: json['osIconAsset']?.toString() ?? '',
    );
  }
}
