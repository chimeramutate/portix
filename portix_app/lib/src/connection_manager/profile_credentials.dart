import '../domain/entities/ssh/ssh_profile.dart' as domain;
import 'profile_secret_store.dart';
import 'ssh_profile.dart';

/// Fills in what a profile needs to connect: secrets from the keychain and
/// its jump host chain. Shared by terminal ([ConnectionManager]) and file
/// ([SftpManager]) connections so both authenticate the same way.
class ProfileCredentials {
  ProfileCredentials({
    ProfileSecretStore? secretStore,
    Future<List<domain.SshProfile>> Function()? savedProfiles,
  }) : _secretStore = secretStore ?? const ProfileSecretStore(),
       _savedProfiles = savedProfiles ?? (() async => const []);

  final ProfileSecretStore _secretStore;
  // Looks up jump host profiles by id.
  final Future<List<domain.SshProfile>> Function() _savedProfiles;
  // Key profiles whose key turned out to be encrypted; only these read the
  // passphrase from the keychain, so unencrypted keys never touch it.
  final Set<String> _keyPassphraseProfiles = {};

  /// Marks [profileId]'s key as encrypted, so connects send the passphrase
  /// saved in the keychain (the slot a password profile uses).
  void useSavedKeyPassphrase(String profileId) =>
      _keyPassphraseProfiles.add(profileId);

  /// Saves a password (or key passphrase) for future connections.
  Future<void> savePassword(String profileId, String password) =>
      _secretStore.savePassword(profileId, password);

  Future<bool> hasSavedPassword(String profileId) async {
    final password = await _secretStore.readPassword(profileId);
    return (password ?? '').trim().isNotEmpty;
  }

  Future<String?> readPassword(String profileId) =>
      _secretStore.readPassword(profileId);

  /// [profile] preceded by its jump hosts, outermost first.
  Future<List<SshProfile>> connectionChain(SshProfile profile) async {
    final chain = [profile];
    var jumpId = profile.jumpProfileId;
    if (jumpId == null) return chain;
    final saved = await _savedProfiles();
    while (jumpId != null) {
      final jump = saved.where((p) => p.id == jumpId).firstOrNull;
      if (jump == null) {
        throw StateError('Jump host profile for ${profile.name} not found.');
      }
      if (chain.any((hop) => hop.id == jump.id)) {
        throw StateError('Jump hosts of ${profile.name} form a loop.');
      }
      final hop = SshProfile.fromDomain(jump);
      chain.insert(0, hop);
      jumpId = hop.jumpProfileId;
    }
    return chain;
  }

  /// [profile] with its secrets and its jump host chain filled in.
  Future<SshProfile> resolve(SshProfile profile) async {
    SshProfile? resolved;
    for (final hop in await connectionChain(profile)) {
      resolved = (await _withSecret(hop)).copyWith(jumpHost: resolved);
    }
    return resolved!;
  }

  Future<SshProfile> _withSecret(SshProfile profile) async {
    if ((profile.privateKeyPath ?? '').trim().isNotEmpty) {
      if (!_keyPassphraseProfiles.contains(profile.id)) return profile;
      final passphrase = await _secretStore
          .readPassword(profile.id)
          .catchError((Object _) => null);
      return (passphrase ?? '').isEmpty
          ? profile
          : profile.copyWith(keyPassphrase: passphrase);
    }
    if ((profile.password ?? '').trim().isNotEmpty) return profile;
    if (!profile.hasPassword) return profile;
    final password = await _secretStore.readPassword(profile.id);
    if ((password ?? '').isEmpty) {
      throw PasswordUnavailableException(profile.name, profile.id);
    }
    return profile.copyWith(password: password);
  }
}

class PasswordUnavailableException implements Exception {
  const PasswordUnavailableException(this.profileName, this.profileId);

  final String profileName;
  final String profileId;

  @override
  String toString() =>
      'Saved password for "$profileName" is not available on this device. '
      'Please re-enter the password.';
}
