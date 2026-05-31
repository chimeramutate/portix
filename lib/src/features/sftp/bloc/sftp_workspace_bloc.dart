import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:portix/src/domain/entities/ssh/index.dart';
import 'package:portix/src/domain/usecases/ssh/index.dart';

part 'sftp_workspace_event.dart';
part 'sftp_workspace_state.dart';

class SftpWorkspaceBloc extends Bloc<SftpWorkspaceEvent, SftpWorkspaceState> {
  SftpWorkspaceBloc({required GetProfiles getProfiles})
    : _getProfiles = getProfiles,
      super(const SftpWorkspaceState()) {
    on<SftpProfilesRequested>(_onProfilesRequested);
    on<SftpProfileSelected>(_onProfileSelected);
    on<SftpProfileCleared>(_onProfileCleared);
  }

  final GetProfiles _getProfiles;

  Future<void> _onProfilesRequested(
    SftpProfilesRequested event,
    Emitter<SftpWorkspaceState> emit,
  ) async {
    emit(state.copyWith(status: SftpWorkspaceStatus.loading));
    final result = await _getProfiles();
    result.fold(
      (failure) => emit(
        state.copyWith(
          status: SftpWorkspaceStatus.failure,
          message: failure.message,
        ),
      ),
      (profiles) => emit(
        state.copyWith(
          status: SftpWorkspaceStatus.ready,
          profiles: profiles,
          message: '',
        ),
      ),
    );
  }

  void _onProfileSelected(
    SftpProfileSelected event,
    Emitter<SftpWorkspaceState> emit,
  ) {
    emit(state.copyWith(selectedProfileId: event.profile.id));
  }

  void _onProfileCleared(
    SftpProfileCleared event,
    Emitter<SftpWorkspaceState> emit,
  ) {
    emit(state.copyWith(clearSelectedProfile: true));
  }
}
