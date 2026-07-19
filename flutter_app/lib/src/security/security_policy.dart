import 'package:flutter/foundation.dart';

class SecurityPolicy extends ChangeNotifier {
  SecurityPolicy();

  Map<String, String> _settings = const {};
  bool _vaultUnlocked = false;

  static const vaultStorageKey = 'access.vault_storage';
  static const requireUnlockBeforeConnectKey =
      'access.require_unlock_before_connect';
  static const localSecureStorageKey = 'access.local_secure_storage';
  static const credentialTimeoutKey = 'access.credential_timeout';
  static const credentialExportKey = 'access.credential_export';

  bool get vaultEnabled => _value(vaultStorageKey, 'Disabled') == 'Enabled';

  bool get requireUnlockBeforeConnect =>
      _value(requireUnlockBeforeConnectKey, 'OFF') == 'ON';

  bool get localSecureStorageEnabled =>
      _value(localSecureStorageKey, 'Enabled') == 'Enabled';

  String get credentialTimeout => _value(credentialTimeoutKey, '20 min');

  String get credentialExportPolicy =>
      _value(credentialExportKey, 'No credentials');

  bool get vaultUnlocked => !vaultEnabled || _vaultUnlocked;

  bool get canReadSecrets =>
      !vaultEnabled || !requireUnlockBeforeConnect || _vaultUnlocked;

  void updateFromSettings(Map<String, String> settings) {
    _settings = Map.unmodifiable(settings);
    if (!vaultEnabled && _vaultUnlocked) {
      _vaultUnlocked = false;
    }
    notifyListeners();
  }

  void markVaultUnlocked() {
    if (!vaultEnabled || _vaultUnlocked) return;
    _vaultUnlocked = true;
    notifyListeners();
  }

  void lockVault() {
    if (!_vaultUnlocked) return;
    _vaultUnlocked = false;
    notifyListeners();
  }

  void ensureSecretReadable() {
    if (canReadSecrets) return;
    throw const VaultLockedException();
  }

  String _value(String key, String fallback) {
    final value = _settings[key]?.trim();
    return value == null || value.isEmpty ? fallback : value;
  }
}

class VaultLockedException implements Exception {
  const VaultLockedException();

  @override
  String toString() {
    return 'Portix Vault is locked. Unlock the vault before using saved credentials.';
  }
}
