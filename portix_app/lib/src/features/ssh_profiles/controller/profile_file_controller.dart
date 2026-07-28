import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:portix/src/domain/entities/ssh/index.dart';

class ProfileFileController {
  const ProfileFileController();

  static const fileExtension = '.portix-profiles.json';
  static const defaultFileName = 'portix-profiles$fileExtension';

  Future<ProfilePathPickResult> pickImportPath() async {
    if (Platform.isMacOS) {
      return _runPicker('osascript', const [
        '-e',
        'POSIX path of (choose file with prompt "Import Portix profile file")',
      ]);
    }
    if (Platform.isWindows) {
      return _runPicker('powershell', const [
        '-NoProfile',
        '-Command',
        r'''
Add-Type -AssemblyName System.Windows.Forms
$dialog = New-Object System.Windows.Forms.OpenFileDialog
$dialog.Filter = "Portix profiles (*.portix-profiles.json)|*.portix-profiles.json|JSON files (*.json)|*.json|All files (*.*)|*.*"
$dialog.Multiselect = $false
if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $dialog.FileName }
''',
      ]);
    }
    // Linux: try zenity first, fall back to file_picker (works in snap).
    final zenityResult = await _runPicker('zenity', const [
      '--file-selection',
      '--title=Import Portix profile file',
      '--file-filter=Portix profiles | *.portix-profiles.json *.json',
    ]);
    if (zenityResult.status != ProfilePathPickStatus.unavailable) {
      return zenityResult;
    }
    return _pickWithFilePicker();
  }

  Future<ProfilePathPickResult> pickExportPath() async {
    if (Platform.isMacOS) {
      return _runPicker('osascript', const [
        '-e',
        'POSIX path of (choose file name with prompt "Export Portix profiles" default name "$defaultFileName")',
      ]);
    }
    if (Platform.isWindows) {
      return _runPicker('powershell', const [
        '-NoProfile',
        '-Command',
        r'''
Add-Type -AssemblyName System.Windows.Forms
$dialog = New-Object System.Windows.Forms.SaveFileDialog
$dialog.Filter = "Portix profiles (*.portix-profiles.json)|*.portix-profiles.json|JSON files (*.json)|*.json"
$dialog.FileName = "portix-profiles.portix-profiles.json"
if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { $dialog.FileName }
''',
      ]);
    }
    // Linux: try zenity first, fall back to file_picker save dialog.
    final zenityResult = await _runPicker('zenity', const [
      '--file-selection',
      '--save',
      '--confirm-overwrite',
      '--title=Export Portix profiles',
      '--filename=portix-profiles.portix-profiles.json',
    ]);
    if (zenityResult.status != ProfilePathPickStatus.unavailable) {
      return zenityResult;
    }
    return _saveWithFilePicker();
  }

  Future<void> exportProfiles(String path, List<SshProfile> profiles) async {
    final file = File(_ensureProfileExtension(path));
    await file.parent.create(recursive: true);
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(
      encoder.convert({
        'schema': 'portix.ssh_profiles',
        'version': 1,
        'exportedAt': DateTime.now().toIso8601String(),
        'profiles': profiles.map(_profileToJson).toList(),
      }),
    );
  }

  Future<List<SshProfile>> importProfiles(
    String path, {
    Set<String> existingIds = const {},
  }) async {
    final file = File(path.trim());
    if (!await file.exists()) {
      throw FileSystemException('Profile file not found', file.path);
    }

    final decoded = jsonDecode(await file.readAsString());
    final rawProfiles = switch (decoded) {
      {'profiles': final List<dynamic> profiles} => profiles,
      final List<dynamic> profiles => profiles,
      final Map<String, dynamic> profile => [profile],
      _ => throw const FormatException('Unsupported Portix profile file.'),
    };

    final usedIds = existingIds.toSet();
    final imported = <SshProfile>[];
    for (var index = 0; index < rawProfiles.length; index += 1) {
      final raw = rawProfiles[index];
      if (raw is! Map) continue;
      final profile = _profileFromJson(Map<String, Object?>.from(raw));
      final id = _uniqueId(profile.id, usedIds, index);
      usedIds.add(id);
      imported.add(profile.copyWith(id: id, status: ConnectionStatus.offline));
    }
    return imported;
  }

  Future<ProfilePathPickResult> _pickWithFilePicker() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) {
        return const ProfilePathPickResult.canceled();
      }
      final path = result.files.single.path;
      if (path == null || path.isEmpty) {
        return const ProfilePathPickResult.canceled();
      }
      return ProfilePathPickResult.selected(path);
    } catch (_) {
      return const ProfilePathPickResult.unavailable();
    }
  }

  Future<ProfilePathPickResult> _saveWithFilePicker() async {
    try {
      final path = await FilePicker.saveFile(
        fileName: defaultFileName,
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (path == null || path.isEmpty) {
        return const ProfilePathPickResult.canceled();
      }
      return ProfilePathPickResult.selected(path);
    } catch (_) {
      return const ProfilePathPickResult.unavailable();
    }
  }

  Future<ProfilePathPickResult> _runPicker(
    String executable,
    List<String> arguments,
  ) async {
    try {
      final result = await Process.run(executable, arguments);
      if (result.exitCode != 0) return const ProfilePathPickResult.canceled();
      final output = result.stdout.toString().trim();
      return output.isEmpty
          ? const ProfilePathPickResult.canceled()
          : ProfilePathPickResult.selected(output);
    } catch (_) {
      return const ProfilePathPickResult.unavailable();
    }
  }

  String _ensureProfileExtension(String path) {
    final trimmed = path.trim();
    if (trimmed.endsWith(fileExtension)) return trimmed;
    if (trimmed.endsWith('.json')) return trimmed;
    return '$trimmed$fileExtension';
  }

  String _uniqueId(String candidate, Set<String> usedIds, int index) {
    final normalized = candidate.trim();
    if (normalized.isNotEmpty && !usedIds.contains(normalized)) {
      return normalized;
    }
    return 'profile-import-${DateTime.now().microsecondsSinceEpoch}-$index';
  }

  Map<String, Object?> _profileToJson(SshProfile profile) {
    return {
      'id': profile.id,
      'name': profile.name,
      'host': profile.host,
      'port': profile.port,
      'username': profile.username,
      'group': profile.group,
      'tags': profile.tags,
      'authMethod': profile.authMethod.name,
      'credentialLabel': profile.authMethod == AuthMethod.password
          ? ''
          : profile.credentialLabel,
      'defaultPath': profile.defaultPath,
      'status': ConnectionStatus.offline.name,
      'color': profile.color.name,
      'startupCommand': profile.startupCommand,
      'terminalFontSize': profile.terminalFontSize,
      'lastUsedLabel': profile.lastUsedLabel,
      'osIconAsset': profile.osIconAsset,
    };
  }

  SshProfile _profileFromJson(Map<String, Object?> json) {
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
          .where((item) => item.trim().isNotEmpty)
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

enum ProfilePathPickStatus { selected, canceled, unavailable }

class ProfilePathPickResult {
  const ProfilePathPickResult._(this.status, [this.path]);

  const ProfilePathPickResult.selected(String path)
    : this._(ProfilePathPickStatus.selected, path);

  const ProfilePathPickResult.canceled()
    : this._(ProfilePathPickStatus.canceled);

  const ProfilePathPickResult.unavailable()
    : this._(ProfilePathPickStatus.unavailable);

  final ProfilePathPickStatus status;
  final String? path;
}
