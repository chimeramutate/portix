import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:portix/src/domain/entities/ssh/index.dart';

part 'ssh_session_event.dart';
part 'ssh_session_state.dart';

enum SshSessionTarget { remoteFolder, sftp }

class SshSessionBloc extends Bloc<SshSessionEvent, SshSessionState> {
  SshSessionBloc() : super(const SshSessionState()) {
    on<SshSessionOpenRequested>(_onOpenRequested);
    on<SshSessionActivated>(_onActivated);
    on<SshSessionCleared>(_onCleared);
    on<SshSessionNavigationConsumed>(_onNavigationConsumed);
  }

  void _onOpenRequested(
    SshSessionOpenRequested event,
    Emitter<SshSessionState> emit,
  ) {
    final profile = event.profile;
    if (!profile.isConnectable || profile.status == ConnectionStatus.draft) {
      emit(
        state.copyWith(
          selectedProfileId: profile.id,
          message: 'Complete host, username, port, and auth before connecting.',
        ),
      );
      return;
    }

    emit(
      state.copyWith(
        selectedProfileId: profile.id,
        targetProfileId: profile.id,
        pendingTarget: event.target,
        clearActiveSession: true,
        openRequestSerial: state.openRequestSerial + 1,
        message: '',
      ),
    );
  }

  void _onActivated(SshSessionActivated event, Emitter<SshSessionState> emit) {
    emit(
      state.copyWith(
        activeSessionId: event.sessionId,
        activeProfileId: event.profileId,
        targetProfileId: event.profileId,
        selectedProfileId: event.profileId,
        connected: event.connected,
        message: '',
      ),
    );
  }

  void _onCleared(SshSessionCleared event, Emitter<SshSessionState> emit) {
    emit(
      state.copyWith(
        clearActiveSession: true,
        clearProfileSelection: true,
        clearPendingTarget: true,
        message: '',
      ),
    );
  }

  void _onNavigationConsumed(
    SshSessionNavigationConsumed event,
    Emitter<SshSessionState> emit,
  ) {
    emit(state.copyWith(clearPendingTarget: true));
  }
}
