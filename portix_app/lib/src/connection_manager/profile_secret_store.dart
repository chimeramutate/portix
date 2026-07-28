import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:portix/src/security/security_policy.dart';

class ProfileSecretStore {
  const ProfileSecretStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
    SecurityPolicy? policy,
  }) : _storage = storage,
       _policy = policy;

  final FlutterSecureStorage _storage;
  final SecurityPolicy? _policy;

  Future<void> savePassword(String profileId, String password) async {
    _policy?.ensureSecretReadable();
    try {
      await _storage.write(key: _passwordKey(profileId), value: password);
    } on PlatformException catch (error) {
      if (_shouldUseMacKeychainFallback(error)) {
        await _writeMacKeychainPassword(profileId, password);
        return;
      }
      if (Platform.isLinux) {
        await _writeLinuxFileFallback(profileId, password);
        return;
      }
      rethrow;
    } on MissingPluginException {
      if (Platform.isLinux) {
        await _writeLinuxFileFallback(profileId, password);
      }
    }
  }

  Future<String?> readPassword(String profileId) async {
    _policy?.ensureSecretReadable();
    try {
      final password = await _storage.read(key: _passwordKey(profileId));
      if (password != null || !Platform.isMacOS) {
        if (password == null && Platform.isLinux) {
          return _readLinuxFileFallback(profileId);
        }
        return password;
      }
      return _readMacKeychainPassword(profileId);
    } on PlatformException catch (error) {
      if (_shouldUseMacKeychainFallback(error)) {
        return _readMacKeychainPassword(profileId);
      }
      if (Platform.isLinux) {
        return _readLinuxFileFallback(profileId);
      }
      rethrow;
    } on MissingPluginException {
      if (Platform.isLinux) {
        return _readLinuxFileFallback(profileId);
      }
      return null;
    }
  }

  Future<void> deletePassword(String profileId) async {
    _policy?.ensureSecretReadable();
    try {
      await _storage.delete(key: _passwordKey(profileId));
      if (Platform.isMacOS) {
        await _deleteMacKeychainPassword(profileId);
      }
      if (Platform.isLinux) {
        await _deleteLinuxFileFallback(profileId);
      }
    } on PlatformException catch (error) {
      if (_shouldUseMacKeychainFallback(error)) {
        await _deleteMacKeychainPassword(profileId);
        return;
      }
      if (Platform.isLinux) {
        await _deleteLinuxFileFallback(profileId);
        return;
      }
      rethrow;
    } on MissingPluginException {
      if (Platform.isLinux) {
        await _deleteLinuxFileFallback(profileId);
      }
    }
  }

  static String _passwordKey(String profileId) {
    return 'portix.ssh_profile.$profileId.password';
  }

  // --- macOS Keychain fallback ---

  static bool _shouldUseMacKeychainFallback(PlatformException error) {
    if (!Platform.isMacOS) {
      return false;
    }
    final details = '${error.code} ${error.message} ${error.details}';
    return details.contains('-34018');
  }

  static Future<void> _writeMacKeychainPassword(
    String profileId,
    String password,
  ) async {
    await _deleteMacKeychainPassword(profileId);
    final result = await Process.run('security', [
      'add-generic-password',
      '-U',
      '-s',
      _macKeychainService,
      '-a',
      profileId,
      '-w',
      password,
    ]);
    if (result.exitCode != 0) {
      throw StateError(
        'Unable to save password to macOS Keychain: ${result.stderr}',
      );
    }
  }

  static Future<String?> _readMacKeychainPassword(String profileId) async {
    final result = await Process.run('security', [
      'find-generic-password',
      '-w',
      '-s',
      _macKeychainService,
      '-a',
      profileId,
    ]);
    if (result.exitCode != 0) {
      return null;
    }
    final value = result.stdout.toString();
    return value.endsWith('\n') ? value.substring(0, value.length - 1) : value;
  }

  static Future<void> _deleteMacKeychainPassword(String profileId) async {
    await Process.run('security', [
      'delete-generic-password',
      '-s',
      _macKeychainService,
      '-a',
      profileId,
    ]);
  }

  static const String _macKeychainService = 'Portix SSH Profile Password';

  // --- Linux file-based fallback ---
  // Used when libsecret / D-Bus Secret Service is not available.
  // Stores credentials as base64-encoded values in a user-only readable file.
  // This is NOT as secure as a proper keyring but allows the app to function.

  static Future<Directory> _linuxSecretDir() async {
    final appDir = await getApplicationSupportDirectory();
    final dir = Directory('${appDir.path}/secrets');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
      // Set directory permissions to owner-only (700).
      await Process.run('chmod', ['700', dir.path]);
    }
    return dir;
  }

  static Future<void> _writeLinuxFileFallback(
    String profileId,
    String password,
  ) async {
    final dir = await _linuxSecretDir();
    final file = File('${dir.path}/${_sanitizeFileName(profileId)}');
    final encoded = base64Encode(utf8.encode(password));
    await file.writeAsString(encoded);
    await Process.run('chmod', ['600', file.path]);
  }

  static Future<String?> _readLinuxFileFallback(String profileId) async {
    final dir = await _linuxSecretDir();
    final file = File('${dir.path}/${_sanitizeFileName(profileId)}');
    if (!await file.exists()) return null;
    try {
      final encoded = await file.readAsString();
      return utf8.decode(base64Decode(encoded.trim()));
    } catch (_) {
      return null;
    }
  }

  static Future<void> _deleteLinuxFileFallback(String profileId) async {
    final dir = await _linuxSecretDir();
    final file = File('${dir.path}/${_sanitizeFileName(profileId)}');
    if (await file.exists()) {
      await file.delete();
    }
  }

  static String _sanitizeFileName(String id) {
    return id.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
  }
}
