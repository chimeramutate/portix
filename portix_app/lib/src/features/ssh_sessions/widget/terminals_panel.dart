import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:portix/src/connection_manager/connection_manager.dart';
import 'package:portix/src/connection_manager/session_models.dart';
import 'package:portix/src/core/theme/app_theme.dart';
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
              _SessionTile(
                session: session,
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

class _SessionTile extends StatelessWidget {
  const _SessionTile({
    required this.session,
    required this.selected,
    required this.onTap,
  });

  final TerminalSession session;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (statusLabel, statusColor) = switch (session.status) {
      ConnectionStatus.connected => ('Connected', AppColors.green),
      ConnectionStatus.connecting => ('Connecting', AppColors.amber),
      ConnectionStatus.disconnected => ('Disconnected', AppColors.muted),
      ConnectionStatus.error => ('Error', AppColors.danger),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? AppColors.selected : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          hoverColor: AppColors.surfaceDark,
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: selected ? AppColors.accent : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.terminal_rounded,
                  size: 16,
                  color: selected ? AppColors.accent : AppColors.muted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        session.title,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: selected ? AppColors.text : AppColors.muted,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Row(
                        children: [
                          Icon(Icons.circle, size: 7, color: statusColor),
                          const SizedBox(width: 5),
                          Text(
                            statusLabel,
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
