import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:portix/src/core/theme/app_theme.dart';
import 'package:portix/src/core/widgets/side_panel.dart';
import 'package:portix/src/features/sftp/bloc/sftp_workspace_bloc.dart';
import 'package:portix/src/features/sftp/page/sftp_workspace_page.dart';

/// Saved servers for the workspace side panel; a click shows that server in
/// an SFTP tab.
class SftpServersPanel extends StatelessWidget {
  const SftpServersPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<SftpWorkspaceBloc>().state;
    final profiles = state.connectableProfiles;
    if (profiles.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Text(
          'No servers yet. Add an SSH profile to browse its files.',
          style: TextStyle(color: AppColors.muted, fontSize: 12),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      children: [
        for (final profile in profiles)
          SidePanelTile(
            icon: Icons.dns_outlined,
            label: profile.name,
            subtitle: Text(
              '${profile.username}@${profile.host}',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: AppColors.muted, fontSize: 11),
            ),
            selected: profile.id == state.selectedProfileId,
            onTap: () => sftpOpenRequests.add(profile),
          ),
      ],
    );
  }
}
