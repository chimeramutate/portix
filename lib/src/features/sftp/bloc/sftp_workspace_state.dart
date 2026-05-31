part of 'sftp_workspace_bloc.dart';

enum SftpWorkspaceStatus { initial, loading, ready, failure }

class SftpWorkspaceState extends Equatable {
  const SftpWorkspaceState({
    this.status = SftpWorkspaceStatus.initial,
    this.profiles = const [],
    this.selectedProfileId,
    this.message = '',
  });

  final SftpWorkspaceStatus status;
  final List<SshProfile> profiles;
  final String? selectedProfileId;
  final String message;

  List<SshProfile> get connectableProfiles => profiles
      .where((profile) => profile.isConnectable)
      .toList(growable: false);

  SshProfile? get selectedProfile {
    final selectedProfileId = this.selectedProfileId;
    if (selectedProfileId == null) return null;
    for (final profile in connectableProfiles) {
      if (profile.id == selectedProfileId) return profile;
    }
    return null;
  }

  String get selectedRemotePath {
    final profile = selectedProfile;
    if (profile == null) return '~';
    final startup = profile.startupCommand.trim();
    final cdMatch = RegExp(r'^cd\s+(.+)$').firstMatch(startup);
    if (cdMatch != null) return cdMatch.group(1)!.trim();
    final defaultPath = profile.defaultPath.trim();
    return defaultPath.isEmpty ? '~' : defaultPath;
  }

  SftpWorkspaceState copyWith({
    SftpWorkspaceStatus? status,
    List<SshProfile>? profiles,
    String? selectedProfileId,
    bool clearSelectedProfile = false,
    String? message,
  }) {
    return SftpWorkspaceState(
      status: status ?? this.status,
      profiles: profiles ?? this.profiles,
      selectedProfileId: clearSelectedProfile
          ? null
          : selectedProfileId ?? this.selectedProfileId,
      message: message ?? this.message,
    );
  }

  @override
  List<Object?> get props => [status, profiles, selectedProfileId, message];
}
