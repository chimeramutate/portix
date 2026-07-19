part of 'ssh_session_bloc.dart';

sealed class SshSessionEvent extends Equatable {
  const SshSessionEvent();

  @override
  List<Object?> get props => [];
}

class SshSessionOpenRequested extends SshSessionEvent {
  const SshSessionOpenRequested({
    required this.profile,
    required this.target,
    this.preferExistingSession = false,
  });

  final SshProfile profile;
  final SshSessionTarget target;
  final bool preferExistingSession;

  @override
  List<Object?> get props => [profile, target, preferExistingSession];
}

class SshSessionActivated extends SshSessionEvent {
  const SshSessionActivated({
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

class SshSessionCleared extends SshSessionEvent {
  const SshSessionCleared();
}

class SshSessionNavigationConsumed extends SshSessionEvent {
  const SshSessionNavigationConsumed();
}
