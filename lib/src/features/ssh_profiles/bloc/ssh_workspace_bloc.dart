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
  }) : _getProfiles = getProfiles,
       _saveProfile = saveProfile,
       _testConnection = testConnection,
       _deleteProfile = deleteProfile,
       super(const SshWorkspaceState()) {
    on<ProfilesRequested>(_onProfilesRequested);
    on<NavigationChanged>(_onNavigationChanged);
    on<GroupFilterChanged>(_onGroupFilterChanged);
    on<SearchChanged>(_onSearchChanged);
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
    on<ProfileDeleted>(_onProfileDeleted);
    on<ProfileConnectRequested>(_onProfileConnectRequested);
    on<ProfileSftpRequested>(_onProfileSftpRequested);
    on<ActiveTerminalSessionChanged>(_onActiveTerminalSessionChanged);
    on<ActiveTerminalSessionCleared>(_onActiveTerminalSessionCleared);
  }

  final GetProfiles _getProfiles;
  final SaveProfile _saveProfile;
  final TestConnection _testConnection;
  final DeleteProfile _deleteProfile;

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
          clearTerminalProfile: true,
          clearActiveSession: true,
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
    emit(
      state.copyWith(
        activeView: WorkspaceView.form,
        editingProfile: SshProfile(
          id: 'profile-${DateTime.now().millisecondsSinceEpoch}',
          name: '',
          host: '',
          port: 22,
          username: '',
          group: 'Production',
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
  ) {
    final profile = state.profiles
        .where((item) => item.id == event.profileId)
        .firstOrNull;
    if (profile == null) return;
    emit(
      state.copyWith(
        selectedId: profile.id,
        editingProfile: profile,
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
            groupFilter: 'All profiles',
            editingProfile: null,
            clearEditingProfile: true,
            activeView: WorkspaceView.gallery,
            message: 'Profile ${saved.name} saved.',
          ),
        );
      },
    );
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
            clearTerminalProfile: event.profileId == state.terminalProfileId,
            clearActiveSession: event.profileId == state.activeSessionProfileId,
            message: 'Profile deleted.',
          ),
        );
      },
    );
  }

  Future<void> _onProfileConnectRequested(
    ProfileConnectRequested event,
    Emitter<SshWorkspaceState> emit,
  ) async {
    await _openProfileSession(
      event.profileId,
      emit,
      targetView: WorkspaceView.remoteFolder,
      openingMessage: 'Opening SSH session...',
    );
  }

  Future<void> _onProfileSftpRequested(
    ProfileSftpRequested event,
    Emitter<SshWorkspaceState> emit,
  ) async {
    await _openProfileSession(
      event.profileId,
      emit,
      targetView: WorkspaceView.sftp,
      openingMessage: 'Opening SFTP workspace...',
    );
  }

  void _onActiveTerminalSessionChanged(
    ActiveTerminalSessionChanged event,
    Emitter<SshWorkspaceState> emit,
  ) {
    emit(
      state.copyWith(
        activeSessionId: event.sessionId,
        activeSessionProfileId: event.profileId,
        terminalProfileId: event.profileId,
        selectedId: event.profileId,
        activeSessionConnected: event.connected,
        message: '',
      ),
    );
  }

  void _onActiveTerminalSessionCleared(
    ActiveTerminalSessionCleared event,
    Emitter<SshWorkspaceState> emit,
  ) {
    emit(
      state.copyWith(
        clearActiveSession: true,
        clearTerminalProfile: true,
        message: '',
      ),
    );
  }

  Future<void> _openProfileSession(
    String profileId,
    Emitter<SshWorkspaceState> emit, {
    required WorkspaceView targetView,
    required String openingMessage,
  }) async {
    final profile = state.profiles.firstWhere((item) => item.id == profileId);
    if (!profile.isConnectable || profile.status == ConnectionStatus.draft) {
      emit(
        state.copyWith(
          isBusy: false,
          selectedId: profile.id,
          message: 'Complete host, username, port, and auth before connecting.',
        ),
      );
      return;
    }
    emit(
      state.copyWith(
        isBusy: false,
        selectedId: profile.id,
        activeView: targetView,
        terminalProfileId: profile.id,
        clearActiveSession: true,
        message: openingMessage,
      ),
    );
  }
}

extension _FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
