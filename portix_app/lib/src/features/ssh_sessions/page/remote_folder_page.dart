import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:portix/src/connection_manager/connection_manager.dart';
import 'package:portix/src/connection_manager/session_models.dart';
import 'package:portix/src/core/di/injection.dart';
import 'package:portix/src/domain/entities/ssh/ssh_profile.dart'
    hide ConnectionStatus;
import 'package:portix/src/features/ssh_profiles/bloc/ssh_workspace_bloc.dart';
import 'package:portix/src/features/ssh_sessions/bloc/ssh_session_bloc.dart';

import '../widget/remote/terminal_panel.dart';

/// The SSH view: terminal tabs only. Files live in the SFTP view.
class RemoteFolderPage extends StatefulWidget {
  const RemoteFolderPage({super.key});

  @override
  State<RemoteFolderPage> createState() => _RemoteFolderPageState();
}

class _RemoteFolderPageState extends State<RemoteFolderPage> {
  late final ConnectionManager _connectionManager = sl<ConnectionManager>();
  String? _activeSessionId;
  int _handledOpenRequestSerial = 0;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SshWorkspaceBloc, SshWorkspaceState>(
      builder: (context, state) {
        final sessionState = context.watch<SshSessionBloc>().state;
        final isVisible = state.activeView == WorkspaceView.remoteFolder;
        final hasNewOpenRequest =
            sessionState.openRequestSerial != _handledOpenRequestSerial;
        if (hasNewOpenRequest) {
          _handledOpenRequestSerial = sessionState.openRequestSerial;
          _activeSessionId = null;
        }
        final requestedProfile = sessionState.profileFrom(state.profiles);
        final activeProfile = _activeProfile(state);
        final shouldUseRequestedProfile =
            hasNewOpenRequest ||
            sessionState.preferExistingSession ||
            (sessionState.activeSessionId == null &&
                sessionState.targetProfileId != null);
        final profile = shouldUseRequestedProfile
            ? requestedProfile ?? activeProfile ?? state.selectedProfile
            : activeProfile ??
                  requestedProfile ??
                  (isVisible ? state.selectedProfile : null);
        final fallbackSession = profile == null
            ? null
            : _connectedSshSessionForProfile(profile.id);
        if (fallbackSession != null &&
            (_activeSessionId == null ||
                !_isSessionConnected(_activeSessionId!))) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _handleActiveSessionChanged(fallbackSession.id);
          });
        }
        if (profile == null) {
          _activeSessionId = null;
          // Stay put, so closing every tab doesn't auto-open a new connection.
          return const SizedBox.shrink();
        }
        return TerminalPanel(
          profile: profile,
          profiles: state.profiles,
          connectRequestId: sessionState.openRequestSerial,
          keyboardEnabled: isVisible,
          onActiveSessionChanged: _handleActiveSessionChanged,
          onLastSessionClosed: () {
            context.read<SshSessionBloc>().add(const SshSessionCleared());
            context.read<SshWorkspaceBloc>()
              ..add(const ProfileSelectionCleared())
              ..add(const NavigationChanged(WorkspaceView.gallery));
          },
        );
      },
    );
  }

  SshProfile? _activeProfile(SshWorkspaceState state) {
    final sessionId = _activeSessionId;
    if (sessionId == null) return null;
    final session = _connectionManager.sessions
        .where((session) => session.id == sessionId)
        .firstOrNull;
    if (session == null) return null;
    return state.profiles
        .where((profile) => profile.id == session.profileId)
        .firstOrNull;
  }

  TerminalSession? _connectedSshSessionForProfile(String profileId) {
    for (final session in _connectionManager.sessions.reversed) {
      if (session.profileId == profileId &&
          session.status == ConnectionStatus.connected) {
        return session;
      }
    }
    return null;
  }

  bool _isSessionConnected(String sessionId) => _connectionManager.sessions.any(
    (session) =>
        session.id == sessionId && session.status == ConnectionStatus.connected,
  );

  void _handleActiveSessionChanged(String? sessionId) {
    if (!mounted || sessionId == _activeSessionId) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || sessionId == _activeSessionId) return;
      setState(() => _activeSessionId = sessionId);
    });
  }
}
