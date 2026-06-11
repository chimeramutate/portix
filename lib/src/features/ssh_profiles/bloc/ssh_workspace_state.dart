part of 'ssh_workspace_bloc.dart';

enum WorkspaceStatus { initial, loading, ready, failure }

enum WorkspaceView { gallery, form, remoteFolder, sftp, rdp, settings }

class SshWorkspaceState extends Equatable {
  const SshWorkspaceState({
    this.status = WorkspaceStatus.initial,
    this.activeView = WorkspaceView.gallery,
    this.profiles = const [],
    this.selectedId,
    this.searchQuery = '',
    this.groupFilter = 'All profiles',
    this.tagFilter = '',
    this.editingProfile,
    this.isBusy = false,
    this.message = '',
  });

  final WorkspaceStatus status;
  final WorkspaceView activeView;
  final List<SshProfile> profiles;
  final String? selectedId;
  final String searchQuery;
  final String groupFilter;
  final String tagFilter;
  final SshProfile? editingProfile;
  final bool isBusy;
  final String message;

  SshProfile? get selectedProfile {
    if (profiles.isEmpty || selectedId == null) return null;
    return profiles.where((item) => item.id == selectedId).firstOrNull;
  }

  List<String> get groups {
    final names = profiles.map((item) => item.group).toSet().toList()..sort();
    return ['All profiles', ...names];
  }

  List<String> get tags {
    final names =
        profiles
            .expand((item) => item.tags)
            .map((tag) => tag.trim())
            .where((tag) => tag.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return names;
  }

  List<SshProfile> get filteredProfiles {
    final normalized = searchQuery.trim().toLowerCase();
    final normalizedTag = tagFilter.trim().toLowerCase();
    return profiles.where((profile) {
      final matchesGroup =
          groupFilter == 'All profiles' || profile.group == groupFilter;
      final matchesTag =
          normalizedTag.isEmpty ||
          profile.tags.any((tag) => tag.toLowerCase() == normalizedTag);
      final text = [
        profile.name,
        profile.host,
        profile.username,
        profile.group,
        ...profile.tags,
      ].join(' ').toLowerCase();
      final matchesSearch = normalized.isEmpty || text.contains(normalized);
      return matchesGroup && matchesTag && matchesSearch;
    }).toList();
  }

  SshProfile? get formProfile => editingProfile;

  bool get isIdentityComplete {
    final profile = formProfile;
    if (profile == null) return false;
    return profile.name.trim().isNotEmpty && profile.group.trim().isNotEmpty;
  }

  bool get isEndpointComplete {
    final profile = formProfile;
    if (profile == null) return false;
    return profile.host.trim().isNotEmpty &&
        profile.port > 0 &&
        profile.port <= 65535 &&
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
    String? searchQuery,
    String? groupFilter,
    String? tagFilter,
    SshProfile? editingProfile,
    bool clearSelection = false,
    bool clearEditingProfile = false,
    bool? isBusy,
    String? message,
  }) {
    return SshWorkspaceState(
      status: status ?? this.status,
      activeView: activeView ?? this.activeView,
      profiles: profiles ?? this.profiles,
      selectedId: clearSelection ? null : selectedId ?? this.selectedId,
      searchQuery: searchQuery ?? this.searchQuery,
      groupFilter: groupFilter ?? this.groupFilter,
      tagFilter: tagFilter ?? this.tagFilter,
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
    searchQuery,
    groupFilter,
    tagFilter,
    editingProfile,
    isBusy,
    message,
  ];
}
