import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:portix/src/connection_manager/connection_manager.dart';
import 'package:portix/src/connection_manager/session_models.dart'
    as session_models;
import 'package:portix/src/core/di/injection.dart';
import 'package:portix/src/core/theme/app_theme.dart';
import 'package:portix/src/core/widgets/index.dart';
import 'package:portix/src/domain/entities/ssh/ssh_profile.dart';
import 'package:portix/src/features/ssh_sessions/bloc/ssh_session_bloc.dart';

import 'package:portix/src/features/ssh_profiles/bloc/ssh_workspace_bloc.dart';

class ProfileCard extends StatelessWidget {
  const ProfileCard({
    required this.profile,
    required this.selected,
    super.key,
    this.previewMode = false,
  });

  final SshProfile profile;
  final bool selected;
  final bool previewMode;

  @override
  Widget build(BuildContext context) {
    final status = effectiveProfileStatus(profile);
    final statusColor = statusColorFor(status);
    return InkWell(
      onTap: previewMode
          ? null
          : () => context.read<SshWorkspaceBloc>().add(
              ProfileSelected(profile.id),
            ),
      borderRadius: BorderRadius.circular(10),
      child: AppPanel(
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        color: selected ? AppColors.selectedSoft : AppColors.surface,
        borderColor: selected ? AppColors.accent : AppColors.border,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ProfileOsIcon(profile: profile, size: 32),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    profile.name.isEmpty ? 'new profile' : profile.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (!previewMode)
                  Tooltip(
                    message: statusLabelFor(status),
                    child: Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        color: statusColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                if (!previewMode)
                  PopupMenuButton<_ProfileAction>(
                    tooltip: 'Profile actions',
                    menuPadding: const EdgeInsets.symmetric(vertical: 4),
                    constraints: const BoxConstraints(minWidth: 170),
                    icon: Icon(
                      Icons.more_horiz_rounded,
                      color: AppColors.muted,
                      size: 18,
                    ),
                    onSelected: (action) {
                      switch (action) {
                        case _ProfileAction.edit:
                          context.read<SshWorkspaceBloc>().add(
                            ProfileEditRequested(profile.id),
                          );
                        case _ProfileAction.duplicate:
                          context.read<SshWorkspaceBloc>().add(
                            ProfileDuplicateRequested(profile.id),
                          );
                        case _ProfileAction.delete:
                          context.read<SshWorkspaceBloc>().add(
                            ProfileDeleted(profile.id),
                          );
                      }
                    },
                    itemBuilder: (context) => [
                      _menuItem(
                        _ProfileAction.edit,
                        Icons.edit_outlined,
                        'Edit',
                      ),
                      _menuItem(
                        _ProfileAction.duplicate,
                        Icons.copy_rounded,
                        'Duplicate',
                      ),
                      PopupMenuDivider(
                        height: 9,
                        color: AppColors.border.withValues(alpha: .6),
                      ),
                      _menuItem(
                        _ProfileAction.delete,
                        Icons.delete_outline_rounded,
                        'Delete',
                        danger: true,
                      ),
                    ],
                  ),
              ],
            ),
            const Spacer(),
            Row(
              children: [
                // One line of pills; extra tags are cut rather than wrapped
                // so every card keeps the same height.
                Expanded(
                  child: SizedBox(
                    height: 20,
                    child: ClipRect(
                      child: Wrap(
                        spacing: 6,
                        clipBehavior: Clip.hardEdge,
                        children: [
                          AppPill(label: profile.group, color: AppColors.muted),
                          for (final tag in profile.tags.take(2))
                            AppPill(label: '#$tag', color: AppColors.muted),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                AppButton(
                  icon: Icons.terminal_rounded,
                  label: previewMode ? 'Open after save' : 'Open SSH',
                  onPressed: previewMode
                      ? null
                      : () => context.read<SshSessionBloc>().add(
                          SshSessionOpenRequested(
                            profile: profile,
                            target: SshSessionTarget.remoteFolder,
                          ),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ServerIcon extends StatelessWidget {
  const ServerIcon({required this.color, super.key, this.size = 38});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color),
      ),
      child: Icon(Icons.dns_rounded, color: color, size: size * .58),
    );
  }
}

class ProfileOsIcon extends StatelessWidget {
  const ProfileOsIcon({required this.profile, super.key, this.size = 38});

  final SshProfile profile;
  final double size;

  @override
  Widget build(BuildContext context) {
    final asset = profile.osIconAsset.trim();
    if (asset.isEmpty) {
      return ServerIcon(color: profileColorFor(profile.color), size: size);
    }
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * .16),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard.withValues(alpha: .55),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: SvgPicture.asset(
        asset,
        fit: BoxFit.contain,
        placeholderBuilder: (_) =>
            ServerIcon(color: profileColorFor(profile.color), size: size),
      ),
    );
  }
}

ConnectionStatus effectiveProfileStatus(SshProfile profile) {
  final sessions = sl<ConnectionManager>().sessions
      .where((session) => session.profileId == profile.id)
      .toList(growable: false);
  if (sessions.isEmpty) return profile.status;
  if (sessions.any(
    (session) => session.status == session_models.ConnectionStatus.connected,
  )) {
    return ConnectionStatus.online;
  }
  if (sessions.any(
    (session) => session.status == session_models.ConnectionStatus.connecting,
  )) {
    return ConnectionStatus.online;
  }
  if (sessions.any(
    (session) => session.status == session_models.ConnectionStatus.error,
  )) {
    return ConnectionStatus.error;
  }
  return ConnectionStatus.offline;
}

Color statusColorFor(ConnectionStatus status) {
  return switch (status) {
    ConnectionStatus.online => AppColors.green,
    ConnectionStatus.offline => AppColors.amber,
    ConnectionStatus.draft => AppColors.amber,
    ConnectionStatus.error => AppColors.danger,
  };
}

String statusLabelFor(ConnectionStatus status) {
  return switch (status) {
    ConnectionStatus.online => 'online',
    ConnectionStatus.offline => 'offline',
    ConnectionStatus.draft => 'draft',
    ConnectionStatus.error => 'error',
  };
}

Color profileColorFor(ProfileColor color) {
  return switch (color) {
    ProfileColor.green => AppColors.green,
    ProfileColor.cyan => AppColors.cyan,
    ProfileColor.blue => AppColors.muted,
    ProfileColor.pink => AppColors.danger,
    ProfileColor.amber => AppColors.amber,
  };
}

enum _ProfileAction { edit, duplicate, delete }

PopupMenuItem<_ProfileAction> _menuItem(
  _ProfileAction action,
  IconData icon,
  String label, {
  bool danger = false,
}) {
  final color = danger ? AppColors.danger : AppColors.text;
  return PopupMenuItem(
    value: action,
    height: 32,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Row(
      children: [
        Icon(icon, size: 16, color: danger ? color : AppColors.muted),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );
}
