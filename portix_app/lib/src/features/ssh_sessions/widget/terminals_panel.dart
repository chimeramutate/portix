import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:portix/src/connection_manager/connection_manager.dart';
import 'package:portix/src/connection_manager/session_models.dart';
import 'package:portix/src/core/theme/app_theme.dart';
import 'package:portix/src/core/widgets/side_panel.dart';
import 'package:portix/src/features/ssh_profiles/bloc/ssh_workspace_bloc.dart';
import 'package:portix/src/features/ssh_sessions/bloc/ssh_session_bloc.dart';

import 'remote/terminal_panel.dart';

/// Open SSH sessions for the workspace side panel; a click shows that
/// session's terminal tab.
class TerminalsPanel extends StatelessWidget {
  const TerminalsPanel({required this.connectionManager, super.key});

  final ConnectionManager connectionManager;

  @override
  Widget build(BuildContext context) {
    final activeId = context.select<SshSessionBloc, String?>(
      (bloc) => bloc.state.activeSessionId,
    );
    return ListenableBuilder(
      listenable: connectionManager,
      builder: (context, _) {
        final sessions = connectionManager.sessions;
        if (sessions.isEmpty) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Text(
              'No open terminals. Connect to a server from Profiles.',
              style: TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          children: [
            for (final session in sessions)
              SidePanelTile(
                icon: Icons.terminal_rounded,
                label: session.title,
                subtitle: _StatusLine(session.status),
                selected: session.id == activeId,
                onTap: () {
                  context.read<SshWorkspaceBloc>().add(
                    const NavigationChanged(WorkspaceView.remoteFolder),
                  );
                  terminalFocusRequests.add(session.id);
                },
              ),
          ],
        );
      },
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine(this.status);

  final ConnectionStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      ConnectionStatus.connected => ('Connected', AppColors.green),
      ConnectionStatus.connecting => ('Connecting', AppColors.amber),
      ConnectionStatus.disconnected => ('Disconnected', AppColors.muted),
      ConnectionStatus.error => ('Error', AppColors.danger),
    };
    return Row(
      children: [
        Icon(Icons.circle, size: 7, color: color),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(color: AppColors.muted, fontSize: 11)),
      ],
    );
  }
}
