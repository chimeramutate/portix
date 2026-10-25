import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:portix/src/core/theme/app_theme.dart';
import 'package:portix/src/core/widgets/side_panel.dart';
import 'package:portix/src/features/ssh_profiles/bloc/ssh_workspace_bloc.dart';

/// Profile groups for the workspace side panel, with the local key
/// encryption note pinned at the bottom.
class GroupSidebar extends StatelessWidget {
  const GroupSidebar({required this.state, super.key});

  final SshWorkspaceState state;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            children: [
              for (final group in state.groups)
                SidePanelTile(
                  icon: group == 'All profiles'
                      ? Icons.dns_outlined
                      : Icons.folder_outlined,
                  label: group,
                  count: group == 'All profiles'
                      ? state.profiles.length
                      : state.profiles
                            .where((profile) => profile.group == group)
                            .length,
                  selected: state.groupFilter == group,
                  onTap: () => context.read<SshWorkspaceBloc>().add(
                    GroupFilterChanged(group),
                  ),
                ),
            ],
          ),
        ),
        Tooltip(
          message:
              'Master password active. SSH keys are encrypted locally before connection.',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  size: 14,
                  color: AppColors.green,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Keys encrypted locally',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
