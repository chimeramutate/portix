import 'package:flutter/material.dart';
import 'package:portix/src/core/theme/app_theme.dart';
import 'package:portix/src/core/widgets/index.dart';

class SettingsActionBar extends StatelessWidget {
  const SettingsActionBar({
    required this.title,
    required this.subtitle,
    required this.dirty,
    required this.busy,
    required this.onReset,
    required this.onRevert,
    required this.onSave,
    super.key,
  });

  final String title;
  final String subtitle;
  final bool dirty;
  final bool busy;
  final VoidCallback onReset;
  final VoidCallback? onRevert;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 560;
          final titleBlock = Row(
            children: [
              const Icon(
                Icons.dashboard_customize_outlined,
                color: AppColors.cyan,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: portixTitle(14),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: portixMuted(11),
                    ),
                  ],
                ),
              ),
            ],
          );
          final actions = Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: compact ? WrapAlignment.start : WrapAlignment.end,
            children: [
              AppButton(
                icon: Icons.restart_alt_rounded,
                label: 'Reset',
                onPressed: busy ? null : onReset,
              ),
              AppButton(
                icon: Icons.undo_rounded,
                label: 'Revert',
                onPressed: busy ? null : onRevert,
              ),
              AppButton(
                icon: Icons.save_outlined,
                label: dirty ? 'Save' : 'Saved',
                primary: true,
                onPressed: busy ? null : onSave,
              ),
            ],
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [titleBlock, const SizedBox(height: 10), actions],
            );
          }
          return Row(
            children: [
              Expanded(child: titleBlock),
              const SizedBox(width: 12),
              actions,
            ],
          );
        },
      ),
    );
  }
}
