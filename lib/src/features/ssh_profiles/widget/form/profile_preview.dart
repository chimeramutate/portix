import 'package:flutter/material.dart';

import 'package:portix/src/core/theme/app_theme.dart';
import 'package:portix/src/domain/entities/ssh/index.dart';
import '../../bloc/index.dart';
import 'package:portix/src/core/widgets/index.dart';

class ProfilePreview extends StatelessWidget {
  const ProfilePreview({required this.state, super.key});

  final SshWorkspaceState state;

  @override
  Widget build(BuildContext context) {
    final profile = state.editingProfile;
    return AppPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Profile Preview',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: portixTitle(19),
          ),
          const SizedBox(height: 14),
          if (profile != null) _PreviewProfileCard(profile: profile),
        ],
      ),
    );
  }
}

class TestConnectionPanel extends StatelessWidget {
  const TestConnectionPanel({required this.state, super.key});

  final SshWorkspaceState state;

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Test Connection',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: portixTitle(19),
          ),
          const SizedBox(height: 18),
          _StatusLine(
            icon: state.isEndpointComplete
                ? Icons.check_circle_outline_rounded
                : Icons.radio_button_unchecked_rounded,
            color: state.isEndpointComplete ? AppColors.green : AppColors.muted,
            title: state.isEndpointComplete
                ? 'Host reachable'
                : 'Endpoint pending',
            subtitle: state.isEndpointComplete
                ? 'TCP handshake ready'
                : 'Fill host, port, username, and path',
          ),
          _StatusLine(
            icon: state.isProfileTested
                ? Icons.check_circle_outline_rounded
                : Icons.timelapse_rounded,
            color: state.isProfileTested
                ? AppColors.green
                : state.isAuthComplete
                ? AppColors.amber
                : AppColors.muted,
            title: state.isProfileTested ? 'Auth verified' : 'Auth not tested',
            subtitle: state.isAuthComplete
                ? 'Click Test Connection'
                : 'Credential label required',
          ),
          _StatusLine(
            icon: Icons.folder_outlined,
            color: state.isProfileTested ? AppColors.green : AppColors.muted,
            title: state.isProfileTested
                ? 'Remote folder ready'
                : 'Remote folder pending',
            subtitle: 'Available after SSH session active',
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.terminal,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              state.isProfileTested
                  ? r'$ ssh connection verified'
                  : state.isEndpointComplete
                  ? r'$ ssh -i key user@host'
                  : r'$ waiting for endpoint...',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.green,
                fontFamily: 'monospace',
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewProfileCard extends StatelessWidget {
  const _PreviewProfileCard({required this.profile});

  final SshProfile profile;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF123455),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primaryBlue),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _PreviewIcon(),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.name,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      profile.address,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              AppPill(label: profile.group, color: AppColors.cyan),
              for (final tag in profile.tags.take(2))
                AppPill(label: tag, color: AppColors.green),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: AppColors.surfaceCard.withValues(alpha: .55),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.terminal_rounded, color: AppColors.muted, size: 16),
                SizedBox(width: 8),
                Text(
                  'Open after save',
                  style: TextStyle(
                    color: AppColors.muted,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
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

class _PreviewIcon extends StatelessWidget {
  const _PreviewIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: AppColors.green.withValues(alpha: .14),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.green),
      ),
      child: const Icon(Icons.dns_rounded, color: AppColors.green, size: 24),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withValues(alpha: .6)),
            ),
            child: Icon(icon, color: color, size: 17),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: portixTitle(13),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: portixMuted(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
