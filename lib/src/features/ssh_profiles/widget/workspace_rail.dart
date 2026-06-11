import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:portix/src/core/theme/app_theme.dart';

import '../bloc/index.dart';

class WorkspaceRail extends StatelessWidget {
  const WorkspaceRail({required this.activeView, super.key});

  final WorkspaceView activeView;

  @override
  Widget build(BuildContext context) {
    final items = [
      (WorkspaceView.gallery, Icons.format_list_bulleted_rounded, 'List SSH'),
      (WorkspaceView.sftp, Icons.cable_rounded, 'SFTP'),
      (WorkspaceView.rdp, Icons.desktop_windows_rounded, 'RDP'),
      (WorkspaceView.settings, Icons.settings_outlined, 'Settings'),
    ];
    return Container(
      width: 68,
      decoration: const BoxDecoration(
        color: AppColors.surfaceDark,
        border: Border(right: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Expanded(
            child: Column(
              children: [
                for (final item in items)
                  _RailItem(
                    selected: item.$1 == activeView,
                    icon: item.$2,
                    label: item.$3,
                    onTap: () => context.read<SshWorkspaceBloc>().add(
                      NavigationChanged(item.$1),
                    ),
                  ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 14),
            child: Column(
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  color: AppColors.green,
                  size: 18,
                ),
                SizedBox(height: 5),
                Text(
                  'Secure',
                  style: TextStyle(
                    color: AppColors.green,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 50,
          height: 54,
          decoration: BoxDecoration(
            color: selected ? AppColors.surfaceCard : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppColors.primaryBlue : Colors.transparent,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: selected ? AppColors.cyan : AppColors.muted,
                size: 18,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? AppColors.text : AppColors.muted,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
