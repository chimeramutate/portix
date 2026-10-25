import 'package:flutter/material.dart';

import 'package:portix/src/core/theme/app_theme.dart';
import 'package:portix/src/domain/entities/ssh/ssh_profile.dart';
import 'package:portix/src/features/ssh_profiles/bloc/ssh_workspace_bloc.dart';
import 'package:portix/src/core/widgets/index.dart';

class ProfilePreview extends StatelessWidget {
  const ProfilePreview({required this.state, super.key});

  final SshWorkspaceState state;

  @override
  Widget build(BuildContext context) {
    final profile = state.editingProfile;
    return AppPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'PREVIEW',
            style: TextStyle(
              color: AppColors.muted,
              fontSize: 11,
              fontWeight: FontWeight.w500,
              letterSpacing: .8,
            ),
          ),
          const SizedBox(height: 10),
          if (profile != null) _PreviewProfileCard(profile: profile),
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
        color: AppColors.surfaceDark,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
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
              AppPill(label: profile.group, color: AppColors.accent),
              for (final tag in profile.tags.take(2))
                AppPill(label: tag, color: AppColors.muted),
            ],
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
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.dns_outlined, color: AppColors.accent, size: 18),
    );
  }
}
