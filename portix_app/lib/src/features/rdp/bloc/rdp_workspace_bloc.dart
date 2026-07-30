import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:portix/src/core/di/injection.dart';
import 'package:portix/src/domain/entities/rdp/index.dart';
import 'package:portix/src/domain/repositories/rdp/index.dart';
import 'package:portix/src/features/rdp/service/rdp_backend_service.dart';
import 'package:portix/src/features/rdp/service/rdp_launch_service.dart';

part 'rdp_workspace_event.dart';
part 'rdp_workspace_state.dart';

class RdpWorkspaceBloc extends Bloc<RdpWorkspaceEvent, RdpWorkspaceState> {
  RdpWorkspaceBloc({
    required RdpProfileRepository repository,
    RdpLaunchService? launchService,
  }) : _repository = repository,
       _launchService =
           launchService ?? RdpLaunchService(repository: repository),
       super(const RdpWorkspaceState()) {
    on<RdpProfilesRequested>(_onProfilesRequested);
    on<RdpNewProfileRequested>(_onNewProfileRequested);
    on<RdpProfileSelected>(_onProfileSelected);
    on<RdpProfileSelectionCleared>(_onProfileSelectionCleared);
    on<RdpProfileEditRequested>(_onProfileEditRequested);
    on<RdpProfileFormChanged>(_onProfileFormChanged);
    on<RdpProfileSaved>(_onProfileSaved);
    on<RdpProfileDeleted>(_onProfileDeleted);
    on<RdpFileImportRequested>(_onFileImportRequested);
    on<RdpLaunchRequested>(_onLaunchRequested);
    on<RdpNavigationChanged>(_onNavigationChanged);
    on<RdpGroupFilterChanged>(_onGroupFilterChanged);
    on<RdpSearchChanged>(_onSearchChanged);
  }

  final RdpProfileRepository _repository;
  final RdpLaunchService _launchService;

  Future<void> _onProfilesRequested(
    RdpProfilesRequested event,
    Emitter<RdpWorkspaceState> emit,
  ) async {
    emit(state.copyWith(status: RdpWorkspaceStatus.loading));
    final result = await _repository.getProfiles();
    result.fold(
      (failure) => emit(
        state.copyWith(
          status: RdpWorkspaceStatus.failure,
          message: failure.message,
        ),
      ),
      (profiles) => emit(
        state.copyWith(
          status: RdpWorkspaceStatus.ready,
          profiles: profiles,
          clearSelection: true,
        ),
      ),
    );
  }

  void _onNewProfileRequested(
    RdpNewProfileRequested event,
    Emitter<RdpWorkspaceState> emit,
  ) {
    emit(
      state.copyWith(
        activeView: RdpView.form,
        editingProfile: RdpProfile(
          id: 'rdp-${DateTime.now().millisecondsSinceEpoch}',
          name: '',
          host: '',
          port: 3389,
          username: '',
          group: state.groupFilter == 'All' ? 'RDP' : state.groupFilter,
          tags: const [],
          color: RdpProfileColor.blue,
          status: RdpProfileStatus.draft,
        ),
        message: '',
      ),
    );
  }

  void _onProfileSelected(
    RdpProfileSelected event,
    Emitter<RdpWorkspaceState> emit,
  ) {
    emit(state.copyWith(selectedId: event.profileId, message: ''));
  }

  void _onProfileSelectionCleared(
    RdpProfileSelectionCleared event,
    Emitter<RdpWorkspaceState> emit,
  ) {
    emit(state.copyWith(clearSelection: true, message: ''));
  }

  void _onProfileEditRequested(
    RdpProfileEditRequested event,
    Emitter<RdpWorkspaceState> emit,
  ) {
    final profile = state.profiles
        .where((p) => p.id == event.profileId)
        .firstOrNull;
    if (profile == null) return;
    emit(
      state.copyWith(
        selectedId: profile.id,
        editingProfile: profile,
        activeView: RdpView.form,
        message: '',
      ),
    );
  }

  void _onProfileFormChanged(
    RdpProfileFormChanged event,
    Emitter<RdpWorkspaceState> emit,
  ) {
    final current = state.editingProfile;
    if (current == null) return;
    emit(
      state.copyWith(
        editingProfile: current.copyWith(
          name: event.name,
          host: event.host,
          port: int.tryParse(event.port) ?? current.port,
          username: event.username,
          password: event.password.isNotEmpty ? event.password : null,
          clearPassword: event.password.isEmpty,
          domain: event.domain.isNotEmpty ? event.domain : null,
          group: event.group,
          desktopWidth:
              int.tryParse(event.desktopWidth) ?? current.desktopWidth,
          desktopHeight:
              int.tryParse(event.desktopHeight) ?? current.desktopHeight,
          fullScreen: event.fullScreen,
          redirectDrives: event.redirectDrives,
          redirectClipboard: event.redirectClipboard,
          enableCredSsp: event.enableCredSsp,
          alternateShell: event.alternateShell,
        ),
        message: '',
      ),
    );
  }

  Future<void> _onProfileSaved(
    RdpProfileSaved event,
    Emitter<RdpWorkspaceState> emit,
  ) async {
    final profile = state.editingProfile;
    if (profile == null) return;

    final validationError = _validate(profile);
    if (validationError != null) {
      emit(state.copyWith(message: validationError));
      return;
    }

    emit(state.copyWith(isBusy: true, message: 'Saving profile...'));
    final result = await _repository.saveProfile(profile);
    result.fold(
      (failure) =>
          emit(state.copyWith(isBusy: false, message: failure.message)),
      (saved) {
        final profiles = [
          saved,
          ...state.profiles.where((p) => p.id != saved.id),
        ];
        emit(
          state.copyWith(
            isBusy: false,
            profiles: profiles,
            selectedId: saved.id,
            clearEditingProfile: true,
            activeView: RdpView.gallery,
            message: 'Profile ${saved.name} saved.',
          ),
        );
      },
    );
  }

  Future<void> _onProfileDeleted(
    RdpProfileDeleted event,
    Emitter<RdpWorkspaceState> emit,
  ) async {
    emit(state.copyWith(isBusy: true));
    final result = await _repository.deleteProfile(event.profileId);
    result.fold(
      (failure) =>
          emit(state.copyWith(isBusy: false, message: failure.message)),
      (_) {
        final profiles = state.profiles
            .where((p) => p.id != event.profileId)
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

  Future<void> _onFileImportRequested(
    RdpFileImportRequested event,
    Emitter<RdpWorkspaceState> emit,
  ) async {
    emit(state.copyWith(isBusy: true, message: 'Importing RDP file...'));
    final result = await _repository.importRdpFile(event.filePath);
    result.fold(
      (failure) =>
          emit(state.copyWith(isBusy: false, message: failure.message)),
      (profile) {
        final profiles = [
          profile,
          ...state.profiles.where((p) => p.id != profile.id),
        ];
        emit(
          state.copyWith(
            isBusy: false,
            profiles: profiles,
            selectedId: profile.id,
            activeView: RdpView.gallery,
            message: 'Imported: ${profile.name}',
          ),
        );
      },
    );
  }

  Future<void> _onLaunchRequested(
    RdpLaunchRequested event,
    Emitter<RdpWorkspaceState> emit,
  ) async {
    final profile = state.profiles
        .where((p) => p.id == event.profileId)
        .firstOrNull;
    if (profile == null) return;

    if (!profile.isConnectable) {
      emit(state.copyWith(message: 'Host is required to connect.'));
      return;
    }

    emit(state.copyWith(isBusy: true, message: 'Launching RDP session...'));
    // First try embedded Rust RDP backend (portix_rdp). If it fails,
    // fallback to external launch via RdpLaunchService.
    try {
      final rdpService = sl<RdpBackendService>();
      // ignore: avoid_print
      print(
        'RDP launch requested for profile ${profile.id} ${profile.address}',
      );
      final backendResult = await rdpService.connect(profile);
      backendResult.fold(
        (failure) async {
          // ignore: avoid_print
          print('RDP embedded connect failed: ${failure.message}');
          // Embedded backend failed — try external launcher as fallback.
          final result = await _launchService.launch(profile);
          result.fold(
            (failure2) {
              // ignore: avoid_print
              print('RDP external launcher failed: ${failure2.message}');
              emit(
                state.copyWith(
                  isBusy: false,
                  message: failure2.message,
                  lastSessionId: null,
                ),
              );
            },
            (launchResult) {
              // ignore: avoid_print
              print(
                'RDP external launcher succeeded: ${launchResult.methodLabel}',
              );
              emit(
                state.copyWith(
                  isBusy: false,
                  lastSessionId: null,
                  lastLaunchResult: 'External: ${launchResult.methodLabel}',
                  message: 'Launched via ${launchResult.methodLabel}',
                ),
              );
            },
          );
        },
        (conn) {
          // ignore: avoid_print
          print('RDP embedded connect succeeded: session=${conn.sessionId}');
          emit(
            state.copyWith(
              isBusy: false,
              lastLaunchResult: 'Embedded RDP backend',
              lastSessionId: conn.sessionId,
              message: 'Launched embedded RDP session (id: ${conn.sessionId})',
            ),
          );
        },
      );
    } catch (error) {
      // ignore: avoid_print
      print('RDP launch caught unexpected error: $error');
      // ignore: avoid_print
      print('RDP launch caught unexpected error: $error');
      // If unexpected error, attempt external launcher as last resort.
      final result = await _launchService.launch(profile);
      result.fold(
        (failure) {
          // ignore: avoid_print
          print('RDP external launcher fallback failed: ${failure.message}');
          emit(
            state.copyWith(
              isBusy: false,
              message: failure.message,
              lastSessionId: null,
            ),
          );
        },
        (launchResult) {
          // ignore: avoid_print
          print(
            'RDP external launcher fallback succeeded: ${launchResult.methodLabel}',
          );
          emit(
            state.copyWith(
              isBusy: false,
              lastSessionId: null,
              lastLaunchResult: launchResult.methodLabel,
              message: 'Launched via ${launchResult.methodLabel}',
            ),
          );
        },
      );
    }
  }

  void _onNavigationChanged(
    RdpNavigationChanged event,
    Emitter<RdpWorkspaceState> emit,
  ) {
    emit(state.copyWith(activeView: event.view, message: ''));
  }

  void _onGroupFilterChanged(
    RdpGroupFilterChanged event,
    Emitter<RdpWorkspaceState> emit,
  ) {
    emit(state.copyWith(groupFilter: event.group));
  }

  void _onSearchChanged(
    RdpSearchChanged event,
    Emitter<RdpWorkspaceState> emit,
  ) {
    emit(state.copyWith(searchQuery: event.query));
  }

  String? _validate(RdpProfile profile) {
    if (profile.name.trim().isEmpty) return 'Profile name is required.';
    if (profile.host.trim().isEmpty) return 'Host / IP is required.';
    if (profile.port <= 0 || profile.port > 65535) {
      return 'Port must be between 1 and 65535.';
    }
    return null;
  }
}
