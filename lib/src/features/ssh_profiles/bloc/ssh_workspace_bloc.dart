import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:portix/src/domain/entities/ssh/index.dart';
import 'package:portix/src/domain/usecases/ssh/index.dart';

part 'ssh_workspace_event.dart';
part 'ssh_workspace_state.dart';

class SshWorkspaceBloc extends Bloc<SshWorkspaceEvent, SshWorkspaceState> {
  SshWorkspaceBloc({
    required GetProfiles getProfiles,
    required SaveProfile saveProfile,
    required TestConnection testConnection,
    required DeleteProfile deleteProfile,
    required ReadPasswordForEdit readPasswordForEdit,
  }) : _getProfiles = getProfiles,
       _saveProfile = saveProfile,
       _testConnection = testConnection,
       _deleteProfile = deleteProfile,
       _readPasswordForEdit = readPasswordForEdit,
       super(const SshWorkspaceState()) {
    on<ProfilesRequested>(_onProfilesRequested);
    on<NavigationChanged>(_onNavigationChanged);
    on<GroupFilterChanged>(_onGroupFilterChanged);
    on<SearchChanged>(_onSearchChanged);
    on<TagFilterChanged>(_onTagFilterChanged);
    on<ProfileSelected>(_onProfileSelected);
    on<ProfileSelectionCleared>(_onProfileSelectionCleared);
    on<NewProfileRequested>(_onNewProfileRequested);
    on<ProfileEditRequested>(_onProfileEditRequested);
    on<ProfileDuplicateRequested>(_onProfileDuplicateRequested);
    on<ProfileFormChanged>(_onProfileFormChanged);
    on<AuthMethodChanged>(_onAuthMethodChanged);
    on<ProfileColorChanged>(_onProfileColorChanged);
    on<ProfileTestRequested>(_onProfileTestRequested);
    on<ProfileSaved>(_onProfileSaved);
    on<ProfilesImported>(_onProfilesImported);
    on<ProfileOsDetected>(_onProfileOsDetected);
    on<ProfileDeleted>(_onProfileDeleted);
  }

  final GetProfiles _getProfiles;
  final SaveProfile _saveProfile;
  final TestConnection _testConnection;
  final DeleteProfile _deleteProfile;
  final ReadPasswordForEdit _readPasswordForEdit;

  Future<void> _onProfilesRequested(
    ProfilesRequested event,
    Emitter<SshWorkspaceState> emit,
  ) async {
    emit(state.copyWith(status: WorkspaceStatus.loading));
    final result = await _getProfiles();
    result.fold(
      (failure) => emit(
        state.copyWith(
          status: WorkspaceStatus.failure,
          message: failure.message,
        ),
      ),
      (profiles) => emit(
        state.copyWith(
          status: WorkspaceStatus.ready,
          profiles: profiles,
          clearSelection: true,
        ),
      ),
    );
  }

  void _onNavigationChanged(
    NavigationChanged event,
    Emitter<SshWorkspaceState> emit,
  ) {
    emit(state.copyWith(activeView: event.view, message: ''));
  }

  void _onGroupFilterChanged(
    GroupFilterChanged event,
    Emitter<SshWorkspaceState> emit,
  ) {
    emit(state.copyWith(groupFilter: event.group, message: ''));
  }

  void _onSearchChanged(SearchChanged event, Emitter<SshWorkspaceState> emit) {
    emit(state.copyWith(searchQuery: event.query, message: ''));
  }

  void _onTagFilterChanged(
    TagFilterChanged event,
    Emitter<SshWorkspaceState> emit,
  ) {
    emit(state.copyWith(tagFilter: event.tag, message: ''));
  }

  void _onProfileSelected(
    ProfileSelected event,
    Emitter<SshWorkspaceState> emit,
  ) {
    emit(
      state.copyWith(
        selectedId: event.profileId,
        activeView: WorkspaceView.gallery,
        message: '',
      ),
    );
  }

  void _onProfileSelectionCleared(
    ProfileSelectionCleared event,
    Emitter<SshWorkspaceState> emit,
  ) {
    emit(state.copyWith(clearSelection: true, message: ''));
  }

  void _onNewProfileRequested(
    NewProfileRequested event,
    Emitter<SshWorkspaceState> emit,
  ) {
    // Use current group filter as default group, or 'Production' if 'All profiles' is selected
    final defaultGroup = state.groupFilter == 'All profiles'
        ? 'Production'
        : state.groupFilter;
    emit(
      state.copyWith(
        activeView: WorkspaceView.form,
        editingProfile: SshProfile(
          id: 'profile-${DateTime.now().millisecondsSinceEpoch}',
          name: '',
          host: '',
          port: 22,
          username: '',
          group: defaultGroup,
          tags: const [],
          authMethod: AuthMethod.sshKey,
          credentialLabel: '',
          defaultPath: '~',
          status: ConnectionStatus.draft,
          color: ProfileColor.green,
          terminalFontSize: 14,
        ),
        message: '',
      ),
    );
  }

  void _onProfileEditRequested(
    ProfileEditRequested event,
    Emitter<SshWorkspaceState> emit,
  ) async {
    final profile = state.profiles
        .where((item) => item.id == event.profileId)
        .firstOrNull;
    if (profile == null) return;

    // For password-auth profiles the stored credentialLabel is the sentinel
    // "Saved password". Read the real password from secure storage so the
    // form field shows the actual value and unhide works correctly.
    SshProfile editableProfile = profile;
    if (profile.authMethod == AuthMethod.password) {
      final realPassword = await _readPasswordForEdit(profile.id);
      if (realPassword != null && realPassword.isNotEmpty) {
        editableProfile = profile.copyWith(credentialLabel: realPassword);
      }
    }

    emit(
      state.copyWith(
        selectedId: profile.id,
        editingProfile: editableProfile,
        activeView: WorkspaceView.form,
        message: '',
      ),
    );
  }

  void _onProfileDuplicateRequested(
    ProfileDuplicateRequested event,
    Emitter<SshWorkspaceState> emit,
  ) {
    final profile = state.profiles
        .where((item) => item.id == event.profileId)
        .firstOrNull;
    if (profile == null) return;
    emit(
      state.copyWith(
        editingProfile: profile.copyWith(
          id: 'profile-${DateTime.now().millisecondsSinceEpoch}',
          name: '${profile.name} copy',
          status: ConnectionStatus.draft,
        ),
        activeView: WorkspaceView.form,
        message: '',
      ),
    );
  }

  void _onProfileFormChanged(
    ProfileFormChanged event,
    Emitter<SshWorkspaceState> emit,
  ) {
    final current = state.editingProfile ?? state.selectedProfile;
    if (current == null) return;
    emit(
      state.copyWith(
        editingProfile: current.copyWith(
          name: event.name,
          host: event.host,
          port: int.tryParse(event.port) ?? current.port,
          username: event.username,
          group: event.group,
          tags: event.tags
              .split(',')
              .map((tag) => tag.trim())
              .where((tag) => tag.isNotEmpty)
              .toList(),
          credentialLabel: event.credentialLabel,
          defaultPath: event.defaultPath,
          startupCommand: event.startupCommand,
          terminalFontSize:
              int.tryParse(event.terminalFontSize) ?? current.terminalFontSize,
        ),
        message: '',
      ),
    );
  }

  void _onAuthMethodChanged(
    AuthMethodChanged event,
    Emitter<SshWorkspaceState> emit,
  ) {
    final current = state.editingProfile;
    if (current == null) return;
    emit(
      state.copyWith(
        editingProfile: current.copyWith(
          authMethod: event.method,
          credentialLabel: '',
        ),
      ),
    );
  }

  void _onProfileColorChanged(
    ProfileColorChanged event,
    Emitter<SshWorkspaceState> emit,
  ) {
    final current = state.editingProfile;
    if (current == null) return;
    emit(
      state.copyWith(
        editingProfile: current.copyWith(color: event.color),
        message: '',
      ),
    );
  }

  Future<void> _onProfileTestRequested(
    ProfileTestRequested event,
    Emitter<SshWorkspaceState> emit,
  ) async {
    final profile = state.editingProfile ?? state.selectedProfile;
    if (profile == null) return;
    final validationMessage = _profileValidationMessage(profile);
    if (validationMessage != null) {
      emit(state.copyWith(message: validationMessage));
      return;
    }
    emit(state.copyWith(isBusy: true, message: 'Testing connection...'));
    final result = await _testConnection(profile);
    result.fold(
      (failure) =>
          emit(state.copyWith(isBusy: false, message: failure.message)),
      (connected) => emit(
        state.copyWith(
          isBusy: false,
          editingProfile: connected,
          message: 'Connection verified for ${connected.name}.',
        ),
      ),
    );
  }

  Future<void> _onProfileSaved(
    ProfileSaved event,
    Emitter<SshWorkspaceState> emit,
  ) async {
    final profile = state.editingProfile;
    if (profile == null) return;
    final validationMessage = _profileValidationMessage(profile);
    if (validationMessage != null) {
      emit(state.copyWith(message: validationMessage));
      return;
    }
    emit(state.copyWith(isBusy: true, message: 'Saving profile...'));
    final result = await _saveProfile(profile);
    result.fold(
      (failure) =>
          emit(state.copyWith(isBusy: false, message: failure.message)),
      (saved) {
        final profiles = [
          saved,
          ...state.profiles.where((item) => item.id != saved.id),
        ];
        emit(
          state.copyWith(
            isBusy: false,
            profiles: profiles,
            selectedId: saved.id,
            searchQuery: '',
            // Preserve the current group filter so user stays in the same group
            groupFilter: state.groupFilter,
            tagFilter: state.tagFilter,
            editingProfile: null,
            clearEditingProfile: true,
            activeView: WorkspaceView.gallery,
            message: 'Profile ${saved.name} saved.',
          ),
        );
      },
    );
  }

  Future<void> _onProfilesImported(
    ProfilesImported event,
    Emitter<SshWorkspaceState> emit,
  ) async {
    if (event.profiles.isEmpty) return;
    emit(state.copyWith(isBusy: true, message: 'Importing profiles...'));

    final savedProfiles = <SshProfile>[];
    for (final profile in event.profiles) {
      final result = await _saveProfile(profile);
      final failure = result.fold((failure) => failure, (_) => null);
      if (failure != null) {
        emit(state.copyWith(isBusy: false, message: failure.message));
        return;
      }
      final saved = result.fold((_) => null, (profile) => profile);
      if (saved != null) savedProfiles.add(saved);
    }

    final importedIds = savedProfiles.map((profile) => profile.id).toSet();
    emit(
      state.copyWith(
        isBusy: false,
        profiles: [
          ...savedProfiles.reversed,
          ...state.profiles.where(
            (profile) => !importedIds.contains(profile.id),
          ),
        ],
        selectedId: savedProfiles.firstOrNull?.id,
        searchQuery: '',
        groupFilter: 'All profiles',
        tagFilter: '',
        activeView: WorkspaceView.gallery,
        message:
            '${savedProfiles.length} profile${savedProfiles.length == 1 ? '' : 's'} imported.',
      ),
    );
  }

  Future<void> _onProfileOsDetected(
    ProfileOsDetected event,
    Emitter<SshWorkspaceState> emit,
  ) async {
    final icon = event.osIconAsset.trim();
    if (icon.isEmpty) return;
    final profile = state.profiles
        .where((item) => item.id == event.profileId)
        .firstOrNull;
    if (profile == null || profile.osIconAsset == icon) return;

    final updated = profile.copyWith(osIconAsset: icon);
    emit(
      state.copyWith(
        profiles: [
          for (final item in state.profiles)
            item.id == updated.id ? updated : item,
        ],
        editingProfile: state.editingProfile?.id == updated.id
            ? updated
            : state.editingProfile,
        message: '',
      ),
    );
    await _saveProfile(updated);
  }

  Future<void> _onProfileDeleted(
    ProfileDeleted event,
    Emitter<SshWorkspaceState> emit,
  ) async {
    emit(state.copyWith(isBusy: true));
    final result = await _deleteProfile(event.profileId);
    result.fold(
      (failure) =>
          emit(state.copyWith(isBusy: false, message: failure.message)),
      (_) {
        final profiles = state.profiles
            .where((item) => item.id != event.profileId)
            .toList();
        emit(
          state.copyWith(
            isBusy: false,
            profiles: profiles,
            clearSelection: event.profileId == state.selectedId,
            message: 'Profile deleted.',
          ),
        );
      },
    );
  }

  String? _profileValidationMessage(SshProfile profile) {
    if (profile.name.trim().isEmpty) {
      return 'Profile name is required.';
    }
    if (profile.group.trim().isEmpty) {
      return 'Profile group is required.';
    }
    if (profile.host.trim().isEmpty) {
      return 'Host / IP is required.';
    }
    if (profile.port <= 0 || profile.port > 65535) {
      return 'Port must be between 1 and 65535.';
    }
    if (profile.username.trim().isEmpty) {
      return 'Username is required.';
    }
    if (profile.credentialLabel.trim().isEmpty) {
      return profile.authMethod == AuthMethod.password
          ? 'Password is required.'
          : 'SSH key path or label is required.';
    }
    return null;
  }
}

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
