import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import 'package:portix/src/core/widgets/index.dart';

import 'package:portix/src/connection_manager/connection_manager.dart';
import 'package:portix/src/connection_manager/session_models.dart'
    as session_models;
import 'package:portix/src/core/di/injection.dart';
import 'package:portix/src/core/theme/app_theme.dart';
import 'package:portix/src/domain/entities/ssh/index.dart';
import 'package:portix/src/features/ssh_sessions/bloc/index.dart';
import '../../bloc/index.dart';

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
        padding: const EdgeInsets.all(12),
        color: selected ? const Color(0xFF123455) : AppColors.surface,
        borderColor: selected ? AppColors.primaryBlue : AppColors.border,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ProfileOsIcon(profile: profile, size: 34),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.name.isEmpty ? 'new profile' : profile.name,
                        overflow: TextOverflow.ellipsis,
                        style: portixTitle(17),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        profile.host.isEmpty ? 'Add host / IP' : profile.host,
                        overflow: TextOverflow.ellipsis,
                        style: portixMuted(),
                      ),
                    ],
                  ),
                ),
                if (!previewMode)
                  PopupMenuButton<_ProfileAction>(
                    tooltip: 'Profile actions',
                    color: AppColors.surfaceCard,
                    icon: const Icon(
                      Icons.more_horiz_rounded,
                      color: AppColors.muted,
                      size: 20,
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
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: _ProfileAction.edit,
                        child: Row(
                          children: [
                            Icon(Icons.edit_rounded, size: 17),
                            SizedBox(width: 10),
                            Text('Edit'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: _ProfileAction.duplicate,
                        child: Row(
                          children: [
                            Icon(Icons.copy_rounded, size: 17),
                            SizedBox(width: 10),
                            Text('Duplicate'),
                          ],
                        ),
                      ),
                      PopupMenuDivider(),
                      PopupMenuItem(
                        value: _ProfileAction.delete,
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline_rounded, size: 17),
                            SizedBox(width: 10),
                            Text('Delete'),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 8),
            MetaLine(
              icon: Icons.person_outline,
              text: profile.username.isEmpty
                  ? 'Set username'
                  : profile.username,
            ),
            MetaLine(icon: Icons.tag_rounded, text: '${profile.port}'),
            MetaLine(
              icon: profile.authMethod == AuthMethod.sshKey
                  ? Icons.key_rounded
                  : Icons.lock_outline_rounded,
              text: profile.credentialLabel.isEmpty
                  ? 'Choose auth'
                  : profile.authMethod == AuthMethod.sshKey
                  ? 'SSH key configured'
                  : 'Password saved securely',
            ),
            const Spacer(),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                AppPill(label: profile.group, color: AppColors.cyan),
                for (final tag in profile.tags.take(previewMode ? 3 : 1))
                  AppPill(label: tag, color: AppColors.green),
                if (!previewMode)
                  AppPill(label: statusLabelFor(status), color: statusColor),
              ],
            ),
            const SizedBox(height: 10),
            if (previewMode)
              SizedBox(
                height: 34,
                child: AppButton(
                  icon: Icons.terminal_rounded,
                  label: 'Open after save',
                  onPressed: null,
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 34,
                      child: AppButton(
                        icon: Icons.terminal_rounded,
                        label: 'Open SSH',
                        onPressed: () => context.read<SshSessionBloc>().add(
                          SshSessionOpenRequested(
                            profile: profile,
                            target: SshSessionTarget.remoteFolder,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  AppIconButton(
                    icon: Icons.folder_copy_outlined,
                    onPressed: () => context.read<SshSessionBloc>().add(
                      SshSessionOpenRequested(
                        profile: profile,
                        target: SshSessionTarget.sftp,
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

class MetaLine extends StatelessWidget {
  const MetaLine({required this.icon, required this.text, super.key});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          Icon(icon, color: AppColors.muted, size: 15),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
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
