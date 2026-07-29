import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:portix/src/core/theme/app_theme.dart';
import 'package:portix/src/core/widgets/index.dart';
import 'package:portix/src/domain/entities/rdp/index.dart';

import '../bloc/index.dart';

class RdpProfileCard extends StatelessWidget {
  const RdpProfileCard({
    required this.profile,
    required this.selected,
    super.key,
  });

  final RdpProfile profile;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final accent = _accentColor(profile.color);
    final borderColor = selected ? accent : AppColors.border;
    final cardBg = selected
        ? AppColors.surfaceCard
        : AppColors.surface;

    return GestureDetector(
      onTap: () => context.read<RdpWorkspaceBloc>().add(
        RdpProfileSelected(profile.id),
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: borderColor, width: selected ? 1.5 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _RdpIcon(color: accent, isCyberArk: profile.isCyberArkPsm),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.name.isEmpty ? 'Unnamed' : profile.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: portixTitle(13),
                      ),
                      Text(
                        profile.address,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: portixMuted(11),
                      ),
                    ],
                  ),
                ),
                _StatusDot(status: profile.status),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (profile.isCyberArkPsm)
                  _Chip(label: 'PSM', color: AppColors.amber),
                if (profile.isCyberArkPsm) const SizedBox(width: 5),
                _Chip(label: profile.group, color: accent.withValues(alpha: .7)),
                const Spacer(),
                Text(
                  '${profile.desktopWidth}×${profile.desktopHeight}',
                  style: portixMuted(10),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RdpIcon extends StatelessWidget {
  const _RdpIcon({required this.color, required this.isCyberArk});

  final Color color;
  final bool isCyberArk;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: .4)),
      ),
      child: Icon(
        isCyberArk ? Icons.shield_rounded : Icons.desktop_windows_rounded,
        color: color,
        size: 18,
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.status});

  final RdpProfileStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      RdpProfileStatus.connected => AppColors.green,
      RdpProfileStatus.connecting => AppColors.amber,
      RdpProfileStatus.error => AppColors.danger,
      _ => AppColors.muted,
    };
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: .3)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w800)),
    );
  }
}

Color _accentColor(RdpProfileColor color) => switch (color) {
  RdpProfileColor.blue => AppColors.primaryBlue,
  RdpProfileColor.cyan => AppColors.cyan,
  RdpProfileColor.green => AppColors.green,
  RdpProfileColor.amber => AppColors.amber,
  RdpProfileColor.pink => AppColors.danger,
};
