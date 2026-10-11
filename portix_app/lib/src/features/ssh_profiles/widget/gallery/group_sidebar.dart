import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:portix/src/core/theme/app_theme.dart';
import 'package:portix/src/features/ssh_profiles/bloc/ssh_workspace_bloc.dart';

const groupSidebarWidth = 228.0;
const groupSidebarCollapsedWidth = 48.0;

/// Flat, scrollable group list. [collapsed] shrinks it to a strip with just
/// the expand button, giving the cards the full width.
class GroupSidebar extends StatelessWidget {
  const GroupSidebar({
    required this.state,
    this.collapsed = false,
    this.onToggle,
    super.key,
  });

  final SshWorkspaceState state;
  final bool collapsed;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final toggle = onToggle == null
        ? null
        : SizedBox.square(
            dimension: 28,
            child: IconButton(
              key: const ValueKey('groups-toggle'),
              tooltip: collapsed ? 'Show groups' : 'Hide groups',
              onPressed: onToggle,
              padding: EdgeInsets.zero,
              icon: Icon(
                collapsed
                    ? Icons.keyboard_double_arrow_right_rounded
                    : Icons.keyboard_double_arrow_left_rounded,
                size: 18,
                color: AppColors.muted,
              ),
            ),
          );
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: collapsed
          ? Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Align(alignment: Alignment.topCenter, child: toggle),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'GROUPS',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: .8,
                          ),
                        ),
                      ),
                      ?toggle,
                    ],
                  ),
                ),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
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
            ),
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
                  color: selected ? AppColors.cyan : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  all ? Icons.dns_outlined : Icons.folder_outlined,
                  size: 16,
                  color: selected ? AppColors.cyan : AppColors.muted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? AppColors.text : AppColors.muted,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
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
                        ? AppColors.cyan.withValues(alpha: .15)
                        : AppColors.surfaceDark,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '$count',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: selected ? AppColors.cyan : AppColors.muted,
                      fontWeight: FontWeight.w600,
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
