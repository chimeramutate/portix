import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';

class ProfileSecretStore {
  const ProfileSecretStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  final FlutterSecureStorage _storage;

  Future<void> savePassword(String profileId, String password) async {
    try {
      await _storage.write(key: _passwordKey(profileId), value: password);
    } on PlatformException catch (error) {
      if (!_shouldUseMacKeychainFallback(error)) {
        rethrow;
      }
      await _writeMacKeychainPassword(profileId, password);
    } on MissingPluginException {
      return;
    }
  }

  Future<String?> readPassword(String profileId) async {
    try {
      final password = await _storage.read(key: _passwordKey(profileId));
      if (password != null || !Platform.isMacOS) {
        return password;
      }
      return _readMacKeychainPassword(profileId);
    } on PlatformException catch (error) {
      if (!_shouldUseMacKeychainFallback(error)) {
        rethrow;
      }
      return _readMacKeychainPassword(profileId);
    } on MissingPluginException {
      return null;
    }
  }

  Future<void> deletePassword(String profileId) async {
    try {
      await _storage.delete(key: _passwordKey(profileId));
      if (Platform.isMacOS) {
        await _deleteMacKeychainPassword(profileId);
      }
    } on PlatformException catch (error) {
      if (!_shouldUseMacKeychainFallback(error)) {
        rethrow;
      }
      await _deleteMacKeychainPassword(profileId);
    } on MissingPluginException {
      return;
    }
  }

  static String _passwordKey(String profileId) {
    return 'portix.ssh_profile.$profileId.password';
  }

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
}
