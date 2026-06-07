import 'package:flutter/material.dart';
import 'package:portix/src/core/theme/app_theme.dart';
import 'package:portix/src/core/widgets/index.dart';
import 'settings_models.dart';

class SettingsNavigationPanel extends StatelessWidget {
  const SettingsNavigationPanel({
    required this.groups,
    required this.selectedId,
    required this.onSelected,
    super.key,
  });

  final List<SettingsNavigationGroup> groups;
  final String selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Settings', style: portixTitle(18)),
          const SizedBox(height: 4),
          Text('Mission control preferences', style: portixMuted(12)),
          const SizedBox(height: 18),
          Expanded(
            child: ListView.separated(
              itemCount: groups.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final group = groups[index];
                return _SettingsNavigationGroupCard(
                  group: group,
                  selectedId: selectedId,
                  onSelected: onSelected,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsNavigationGroupCard extends StatelessWidget {
  const _SettingsNavigationGroupCard({
    required this.group,
    required this.selectedId,
    required this.onSelected,
  });

  final SettingsNavigationGroup group;
  final String selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      padding: const EdgeInsets.all(8),
      color: AppColors.surfaceCard.withValues(alpha: .42),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(group.label, style: portixMuted(11)),
          ),
          for (final item in group.items) ...[
            _SettingsNavigationTile(
              item: item,
              active: item.id == selectedId,
              onTap: () => onSelected(item.id),
            ),
            if (item != group.items.last) const SizedBox(height: 7),
          ],
        ],
      ),
    );
  }
}

class _SettingsNavigationTile extends StatelessWidget {
  const _SettingsNavigationTile({
    required this.item,
    required this.active,
    required this.onTap,
  });

  final SettingsNavigationItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.cyan : AppColors.muted;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: active
                ? AppColors.primaryBlue.withValues(alpha: .22)
                : AppColors.surfaceDark.withValues(alpha: .54),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active ? AppColors.primaryBlue : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 3,
                height: 20,
                decoration: BoxDecoration(
                  color: active ? AppColors.cyan : AppColors.border,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(width: 12),
              Icon(item.icon, color: color, size: 16),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  item.title,
                  overflow: TextOverflow.ellipsis,
                  style: portixTitle(
                    12,
                  ).copyWith(color: active ? AppColors.text : AppColors.muted),
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: color, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
