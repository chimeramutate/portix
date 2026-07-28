part of 'ssh_session_bloc.dart';

class SshSessionState extends Equatable {
  const SshSessionState({
    this.selectedProfileId,
    this.targetProfileId,
    this.activeSessionId,
    this.activeProfileId,
    this.connected = false,
    this.pendingTarget,
    this.message = '',
    this.openRequestSerial = 0,
    this.preferExistingSession = false,
  });

  final String? selectedProfileId;
  final String? targetProfileId;
  final String? activeSessionId;
  final String? activeProfileId;
  final bool connected;
  final SshSessionTarget? pendingTarget;
  final String message;
  final int openRequestSerial;
  final bool preferExistingSession;

  bool get hasActiveSession =>
      activeSessionId != null && activeProfileId != null && connected;

  bool get canReturnToSsh =>
      activeSessionId != null ||
      activeProfileId != null ||
      targetProfileId != null ||
      selectedProfileId != null;

  SshProfile? profileFrom(List<SshProfile> profiles) {
    final id = activeProfileId ?? targetProfileId ?? selectedProfileId;
    if (id == null) return null;
    for (final profile in profiles) {
      if (profile.id == id) return profile;
    }
    return null;
  }

  String defaultPathFor(List<SshProfile> profiles) {
    final profile = profileFrom(profiles);
    if (profile == null) return '~';
    final startup = profile.startupCommand.trim();
    final cdMatch = RegExp(r'^cd\s+(.+)$').firstMatch(startup);
    if (cdMatch != null) return cdMatch.group(1)!.trim();
    final defaultPath = profile.defaultPath.trim();
    return defaultPath.isEmpty ? '~' : defaultPath;
  }

  SshSessionState copyWith({
    String? selectedProfileId,
    String? targetProfileId,
    String? activeSessionId,
    String? activeProfileId,
    bool? connected,
    SshSessionTarget? pendingTarget,
    bool? preferExistingSession,
    bool clearPendingTarget = false,
    bool clearActiveSession = false,
    bool clearProfileSelection = false,
    String? message,
    int? openRequestSerial,
  }) {
    return SshSessionState(
      selectedProfileId: clearProfileSelection
          ? null
          : selectedProfileId ?? this.selectedProfileId,
      targetProfileId: clearProfileSelection
          ? null
          : targetProfileId ?? this.targetProfileId,
      activeSessionId: clearActiveSession
          ? null
          : activeSessionId ?? this.activeSessionId,
      activeProfileId: clearActiveSession
          ? null
          : activeProfileId ?? this.activeProfileId,
      connected: clearActiveSession ? false : connected ?? this.connected,
      pendingTarget: clearPendingTarget
          ? null
          : pendingTarget ?? this.pendingTarget,
      message: message ?? this.message,
      openRequestSerial: openRequestSerial ?? this.openRequestSerial,
      preferExistingSession:
          preferExistingSession ?? this.preferExistingSession,
    );
  }

  @override
  List<Object?> get props => [
    selectedProfileId,
    targetProfileId,
    activeSessionId,
    activeProfileId,
    connected,
    pendingTarget,
    message,
    openRequestSerial,
    preferExistingSession,
  ];
}
