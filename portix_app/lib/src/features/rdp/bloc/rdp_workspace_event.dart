part of 'rdp_workspace_bloc.dart';

sealed class RdpWorkspaceEvent extends Equatable {
  const RdpWorkspaceEvent();

  @override
  List<Object?> get props => [];
}

class RdpProfilesRequested extends RdpWorkspaceEvent {
  const RdpProfilesRequested();
}

class RdpNewProfileRequested extends RdpWorkspaceEvent {
  const RdpNewProfileRequested();
}

class RdpProfileSelected extends RdpWorkspaceEvent {
  const RdpProfileSelected(this.profileId);
  final String profileId;

  @override
  List<Object?> get props => [profileId];
}

class RdpProfileSelectionCleared extends RdpWorkspaceEvent {
  const RdpProfileSelectionCleared();
}

class RdpProfileEditRequested extends RdpWorkspaceEvent {
  const RdpProfileEditRequested(this.profileId);
  final String profileId;

  @override
  List<Object?> get props => [profileId];
}

class RdpProfileFormChanged extends RdpWorkspaceEvent {
  const RdpProfileFormChanged({
    required this.name,
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    required this.domain,
    required this.group,
    required this.desktopWidth,
    required this.desktopHeight,
    required this.fullScreen,
    required this.redirectDrives,
    required this.redirectClipboard,
    required this.enableCredSsp,
    required this.alternateShell,
  });

  final String name;
  final String host;
  final String port;
  final String username;
  final String password;
  final String domain;
  final String group;
  final String desktopWidth;
  final String desktopHeight;
  final bool fullScreen;
  final bool redirectDrives;
  final bool redirectClipboard;
  final bool enableCredSsp;
  final String alternateShell;

  @override
  List<Object?> get props => [
    name, host, port, username, password, domain, group,
    desktopWidth, desktopHeight, fullScreen, redirectDrives,
    redirectClipboard, enableCredSsp, alternateShell,
  ];
}

class RdpProfileSaved extends RdpWorkspaceEvent {
  const RdpProfileSaved();
}

class RdpProfileDeleted extends RdpWorkspaceEvent {
  const RdpProfileDeleted(this.profileId);
  final String profileId;

  @override
  List<Object?> get props => [profileId];
}

class RdpFileImportRequested extends RdpWorkspaceEvent {
  const RdpFileImportRequested(this.filePath);
  final String filePath;

  @override
  List<Object?> get props => [filePath];
}

class RdpLaunchRequested extends RdpWorkspaceEvent {
  const RdpLaunchRequested(this.profileId);
  final String profileId;

  @override
  List<Object?> get props => [profileId];
}

class RdpNavigationChanged extends RdpWorkspaceEvent {
  const RdpNavigationChanged(this.view);
  final RdpView view;

  @override
  List<Object?> get props => [view];
}

class RdpGroupFilterChanged extends RdpWorkspaceEvent {
  const RdpGroupFilterChanged(this.group);
  final String group;

  @override
  List<Object?> get props => [group];
}

class RdpSearchChanged extends RdpWorkspaceEvent {
  const RdpSearchChanged(this.query);
  final String query;

  @override
  List<Object?> get props => [query];
}
