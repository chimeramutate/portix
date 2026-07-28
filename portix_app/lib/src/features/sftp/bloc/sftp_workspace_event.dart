part of 'sftp_workspace_bloc.dart';

sealed class SftpWorkspaceEvent extends Equatable {
  const SftpWorkspaceEvent();

  @override
  List<Object?> get props => const [];
}

class SftpProfilesRequested extends SftpWorkspaceEvent {
  const SftpProfilesRequested();
}

class SftpProfileSelected extends SftpWorkspaceEvent {
  const SftpProfileSelected(this.profile);

  final SshProfile profile;

  @override
  List<Object?> get props => [profile];
}

class SftpProfileCleared extends SftpWorkspaceEvent {
  const SftpProfileCleared();
}
