part of 'ssh_workspace_bloc.dart';

sealed class SshWorkspaceEvent extends Equatable {
  const SshWorkspaceEvent();

  @override
  List<Object?> get props => [];
}

class ProfilesRequested extends SshWorkspaceEvent {
  const ProfilesRequested();
}

class NavigationChanged extends SshWorkspaceEvent {
  const NavigationChanged(this.view);
  final WorkspaceView view;

  @override
  List<Object?> get props => [view];
}

class GroupFilterChanged extends SshWorkspaceEvent {
  const GroupFilterChanged(this.group);
  final String group;

  @override
  List<Object?> get props => [group];
}

class SearchChanged extends SshWorkspaceEvent {
  const SearchChanged(this.query);
  final String query;

  @override
  List<Object?> get props => [query];
}

class ProfileSelected extends SshWorkspaceEvent {
  const ProfileSelected(this.profileId);
  final String profileId;

  @override
  List<Object?> get props => [profileId];
}

class ProfileSelectionCleared extends SshWorkspaceEvent {
  const ProfileSelectionCleared();
}

class NewProfileRequested extends SshWorkspaceEvent {
  const NewProfileRequested();
}

class ProfileEditRequested extends SshWorkspaceEvent {
  const ProfileEditRequested(this.profileId);

  final String profileId;

  @override
  List<Object?> get props => [profileId];
}

class ProfileDuplicateRequested extends SshWorkspaceEvent {
  const ProfileDuplicateRequested(this.profileId);

  final String profileId;

  @override
  List<Object?> get props => [profileId];
}

class ProfileFormChanged extends SshWorkspaceEvent {
  const ProfileFormChanged({
    required this.name,
    required this.host,
    required this.port,
    required this.username,
    required this.group,
    required this.tags,
    required this.credentialLabel,
    required this.defaultPath,
    required this.startupCommand,
    required this.terminalFontSize,
  });

  final String name;
  final String host;
  final String port;
  final String username;
  final String group;
  final String tags;
  final String credentialLabel;
  final String defaultPath;
  final String startupCommand;
  final String terminalFontSize;

  @override
  List<Object?> get props => [
    name,
    host,
    port,
    username,
    group,
    tags,
    credentialLabel,
    defaultPath,
    startupCommand,
    terminalFontSize,
  ];
}

class AuthMethodChanged extends SshWorkspaceEvent {
  const AuthMethodChanged(this.method);
  final AuthMethod method;

  @override
  List<Object?> get props => [method];
}

class ProfileColorChanged extends SshWorkspaceEvent {
  const ProfileColorChanged(this.color);
  final ProfileColor color;

  @override
  List<Object?> get props => [color];
}

class ProfileTestRequested extends SshWorkspaceEvent {
  const ProfileTestRequested();
}

class ProfileSaved extends SshWorkspaceEvent {
  const ProfileSaved();
}

class ProfileDeleted extends SshWorkspaceEvent {
  const ProfileDeleted(this.profileId);
  final String profileId;

  @override
  List<Object?> get props => [profileId];
}

class ProfileConnectRequested extends SshWorkspaceEvent {
  const ProfileConnectRequested(this.profileId);
  final String profileId;

  @override
  List<Object?> get props => [profileId];
}

class ProfileSftpRequested extends SshWorkspaceEvent {
  const ProfileSftpRequested(this.profileId);
  final String profileId;

  @override
  List<Object?> get props => [profileId];
}

class ActiveTerminalSessionChanged extends SshWorkspaceEvent {
  const ActiveTerminalSessionChanged({
    required this.sessionId,
    required this.profileId,
    required this.connected,
  });

  final String sessionId;
  final String profileId;
  final bool connected;

  @override
  List<Object?> get props => [sessionId, profileId, connected];
}

class ActiveTerminalSessionCleared extends SshWorkspaceEvent {
  const ActiveTerminalSessionCleared();
}
