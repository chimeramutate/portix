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

// TestConnectionPanel and _StatusLine removed – test connection feature is no longer part of the profile form.


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

// _StatusLine removed – no longer needed after TestConnectionPanel was removed.
