import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:portix/src/core/theme/app_theme.dart';
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
                _GroupTile(
                  label: group,
                  all: group == 'All profiles',
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

class _GroupTile extends StatelessWidget {
  const _GroupTile({
    required this.label,
    required this.all,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool all;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
            height: 32,
            padding: const EdgeInsets.only(left: 8, right: 8),
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
                  all ? Icons.dns_outlined : Icons.folder_outlined,
                  size: 16,
                  color: selected ? AppColors.accent : AppColors.muted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? AppColors.text : AppColors.muted,
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
                  ),
                ),
                Container(
                  constraints: const BoxConstraints(minWidth: 22),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.accent.withValues(alpha: .15)
                        : AppColors.surfaceDark,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '$count',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: selected ? AppColors.accent : AppColors.muted,
                      fontWeight: FontWeight.w400,
                      fontSize: 11,
                    ),
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
