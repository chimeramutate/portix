import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:portix/src/core/widgets/index.dart';

import 'package:portix/src/core/theme/app_theme.dart';
import '../../bloc/index.dart';

class GroupSidebar extends StatelessWidget {
  const GroupSidebar({required this.state, super.key});

  final SshWorkspaceState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Groups', style: portixLabel()),
          const SizedBox(height: 10),
          for (final group in state.groups)
            _GroupTile(
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
          const SizedBox(height: 18),
          const _InfoPanel(
            title: 'Security state',
            body:
                'Master password active. SSH keys are encrypted locally before connection.',
            icon: Icons.lock_outline_rounded,
          ),
        ],
      ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  const _GroupTile({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF143B63) : AppColors.surfaceDark,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? AppColors.primaryBlue : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? AppColors.text : AppColors.muted,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
              Text(
                '$count',
                style: TextStyle(
                  color: selected ? AppColors.cyan : AppColors.muted,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({
    required this.title,
    required this.body,
    required this.icon,
  });

  final String title;
  final String body;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: AppColors.green, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: portixTitle(13))),
            ],
          ),
          const SizedBox(height: 10),
          Text(body, style: portixMuted(), softWrap: true),
        ],
      ),
    );
  }
}
