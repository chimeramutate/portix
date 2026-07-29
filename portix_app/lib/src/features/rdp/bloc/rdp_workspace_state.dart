part of 'rdp_workspace_bloc.dart';

enum RdpWorkspaceStatus { initial, loading, ready, failure }

enum RdpView { gallery, form }

class RdpWorkspaceState extends Equatable {
  const RdpWorkspaceState({
    this.status = RdpWorkspaceStatus.initial,
    this.activeView = RdpView.gallery,
    this.profiles = const [],
    this.selectedId,
    this.editingProfile,
    this.groupFilter = 'All',
    this.searchQuery = '',
    this.isBusy = false,
    this.message = '',
    this.lastLaunchResult,
  });

  final RdpWorkspaceStatus status;
  final RdpView activeView;
  final List<RdpProfile> profiles;
  final String? selectedId;
  final RdpProfile? editingProfile;
  final String groupFilter;
  final String searchQuery;
  final bool isBusy;
  final String message;
  final String? lastLaunchResult;

  RdpProfile? get selectedProfile {
    if (profiles.isEmpty || selectedId == null) return null;
    return profiles.where((p) => p.id == selectedId).firstOrNull;
  }

  List<String> get groups {
    final names = profiles.map((p) => p.group).toSet().toList()..sort();
    return ['All', ...names];
  }

  List<RdpProfile> get filteredProfiles {
    final normalized = searchQuery.trim().toLowerCase();
    return profiles.where((p) {
      final matchesGroup = groupFilter == 'All' || p.group == groupFilter;
      final text = [p.name, p.host, p.username, p.group].join(' ').toLowerCase();
      final matchesSearch = normalized.isEmpty || text.contains(normalized);
      return matchesGroup && matchesSearch;
    }).toList();
  }

  RdpWorkspaceState copyWith({
    RdpWorkspaceStatus? status,
    RdpView? activeView,
    List<RdpProfile>? profiles,
    String? selectedId,
    bool clearSelection = false,
    RdpProfile? editingProfile,
    bool clearEditingProfile = false,
    String? groupFilter,
    String? searchQuery,
    bool? isBusy,
    String? message,
    String? lastLaunchResult,
    bool clearLastLaunchResult = false,
  }) {
    return RdpWorkspaceState(
      status: status ?? this.status,
      activeView: activeView ?? this.activeView,
      profiles: profiles ?? this.profiles,
      selectedId: clearSelection ? null : selectedId ?? this.selectedId,
      editingProfile: clearEditingProfile ? null : editingProfile ?? this.editingProfile,
      groupFilter: groupFilter ?? this.groupFilter,
      searchQuery: searchQuery ?? this.searchQuery,
      isBusy: isBusy ?? this.isBusy,
      message: message ?? this.message,
      lastLaunchResult: clearLastLaunchResult
          ? null
          : lastLaunchResult ?? this.lastLaunchResult,
    );
  }

  @override
  List<Object?> get props => [
    status, activeView, profiles, selectedId, editingProfile,
    groupFilter, searchQuery, isBusy, message, lastLaunchResult,
  ];
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
