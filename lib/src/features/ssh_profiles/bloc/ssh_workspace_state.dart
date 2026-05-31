part of 'ssh_workspace_bloc.dart';

enum WorkspaceStatus { initial, loading, ready, failure }

enum WorkspaceView { gallery, form, remoteFolder, sftp, settings }

class SshWorkspaceState extends Equatable {
  const SshWorkspaceState({
    this.status = WorkspaceStatus.initial,
    this.activeView = WorkspaceView.gallery,
    this.profiles = const [],
    this.selectedId,
    this.terminalProfileId,
    this.activeSessionId,
    this.activeSessionProfileId,
    this.activeSessionConnected = false,
    this.searchQuery = '',
    this.groupFilter = 'All profiles',
    this.editingProfile,
    this.isBusy = false,
    this.message = '',
  });

  final WorkspaceStatus status;
  final WorkspaceView activeView;
  final List<SshProfile> profiles;
  final String? selectedId;
  final String? terminalProfileId;
  final String? activeSessionId;
  final String? activeSessionProfileId;
  final bool activeSessionConnected;
  final String searchQuery;
  final String groupFilter;
  final SshProfile? editingProfile;
  final bool isBusy;
  final String message;

  SshProfile? get selectedProfile {
    if (profiles.isEmpty || selectedId == null) return null;
    return profiles.where((item) => item.id == selectedId).firstOrNull;
  }

  SshProfile? get activeSessionProfile {
    if (profiles.isEmpty || activeSessionProfileId == null) return null;
    return profiles
        .where((item) => item.id == activeSessionProfileId)
        .firstOrNull;
  }

  SshProfile? get terminalProfile {
    if (profiles.isEmpty) return null;
    return activeSessionProfile ??
        profiles.where((item) => item.id == terminalProfileId).firstOrNull ??
        selectedProfile;
  }

  // Compatibility getter untuk file lama yang masih membaca activeTerminalProfile.
  // Source of truth tetap activeSessionProfile dari tab session aktif.
  SshProfile? get activeTerminalProfile =>
      activeSessionProfile ?? terminalProfile;

  bool get hasActiveTerminalSession =>
      activeSessionId != null &&
      activeSessionConnected &&
      activeTerminalProfile != null;

  String get activeTerminalDefaultPath {
    final profile = activeTerminalProfile;
    if (profile == null) return '~';

    final startup = profile.startupCommand.trim();
    final cdMatch = RegExp(r'^cd\s+(.+)$').firstMatch(startup);
    if (cdMatch != null) return cdMatch.group(1)!.trim();

    final defaultPath = profile.defaultPath.trim();
    return defaultPath.isEmpty ? '~' : defaultPath;
  }

  List<String> get groups {
    final names = profiles.map((item) => item.group).toSet().toList()..sort();
    return ['All profiles', ...names];
  }

  List<SshProfile> get filteredProfiles {
    final normalized = searchQuery.trim().toLowerCase();
    return profiles.where((profile) {
      final matchesGroup =
          groupFilter == 'All profiles' || profile.group == groupFilter;
      final text = [
        profile.name,
        profile.host,
        profile.username,
        profile.group,
        ...profile.tags,
      ].join(' ').toLowerCase();
      final matchesSearch = normalized.isEmpty || text.contains(normalized);
      return matchesGroup && matchesSearch;
    }).toList();
  }

  SshProfile? get formProfile => editingProfile;

  bool get isIdentityComplete {
    final profile = formProfile;
    if (profile == null) return false;
    return profile.name.trim().isNotEmpty &&
        profile.group.trim().isNotEmpty &&
        profile.tags.isNotEmpty;
  }

  bool get isEndpointComplete {
    final profile = formProfile;
    if (profile == null) return false;
    return profile.host.trim().isNotEmpty &&
        profile.port.toString().trim().isNotEmpty &&
        profile.username.trim().isNotEmpty;
  }

  bool get isAuthComplete {
    final profile = formProfile;
    if (profile == null) return false;
    return profile.credentialLabel.trim().isNotEmpty;
  }

  bool get isProfileTested => formProfile?.status == ConnectionStatus.online;

  bool get isProfileFormComplete =>
      isIdentityComplete && isEndpointComplete && isAuthComplete;

  SshWorkspaceState copyWith({
    WorkspaceStatus? status,
    WorkspaceView? activeView,
    List<SshProfile>? profiles,
    String? selectedId,
    String? terminalProfileId,
    String? activeSessionId,
    String? activeSessionProfileId,
    bool? activeSessionConnected,
    String? searchQuery,
    String? groupFilter,
    SshProfile? editingProfile,
    bool clearSelection = false,
    bool clearEditingProfile = false,
    bool clearTerminalProfile = false,
    bool clearActiveSession = false,
    bool? isBusy,
    String? message,
  }) {
    return SshWorkspaceState(
      status: status ?? this.status,
      activeView: activeView ?? this.activeView,
      profiles: profiles ?? this.profiles,
      selectedId: clearSelection ? null : selectedId ?? this.selectedId,
      terminalProfileId: clearTerminalProfile
          ? null
          : terminalProfileId ?? this.terminalProfileId,
      activeSessionId: clearActiveSession
          ? null
          : activeSessionId ?? this.activeSessionId,
      activeSessionProfileId: clearActiveSession
          ? null
          : activeSessionProfileId ?? this.activeSessionProfileId,
      activeSessionConnected: clearActiveSession
          ? false
          : activeSessionConnected ?? this.activeSessionConnected,
      searchQuery: searchQuery ?? this.searchQuery,
      groupFilter: groupFilter ?? this.groupFilter,
      editingProfile: clearEditingProfile
          ? null
          : editingProfile ?? this.editingProfile,
      isBusy: isBusy ?? this.isBusy,
      message: message ?? this.message,
    );
  }

  @override
  List<Object?> get props => [
    status,
    activeView,
    profiles,
    selectedId,
    terminalProfileId,
    activeSessionId,
    activeSessionProfileId,
    activeSessionConnected,
    searchQuery,
    groupFilter,
    editingProfile,
    isBusy,
    message,
  ];
}
