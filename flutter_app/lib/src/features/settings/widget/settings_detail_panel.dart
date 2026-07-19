import 'package:flutter/material.dart';
import 'package:portix/src/core/theme/app_theme.dart';
import 'package:portix/src/core/widgets/index.dart';
import 'settings_models.dart';

class SettingsDetailPanel extends StatelessWidget {
  const SettingsDetailPanel({
    required this.item,
    required this.values,
    required this.defaults,
    required this.lastSavedAt,
    required this.dirty,
    required this.onChanged,
    required this.onRevert,
    required this.onSave,
    super.key,
  });

  final SettingsNavigationItem item;
  final Map<String, String> values;
  final Map<String, String> defaults;
  final DateTime? lastSavedAt;
  final bool dirty;
  final void Function(String key, String value) onChanged;
  final VoidCallback? onRevert;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          _SettingsProfileHeader(item: item, dirty: dirty),
          const SizedBox(height: 12),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Calculate card height based on max row count across sections.
                // row height(28) + spacing(7) = 35 per row, title(20) + gap(8) + padding(20) = 48
                final maxRows = item.sections.isEmpty
                    ? 3
                    : item.sections
                          .map((s) => s.rows.length)
                          .reduce((a, b) => a > b ? a : b);
                final cardHeight = 48.0 + maxRows * 35.0;

                return GridView.builder(
                  itemCount: item.sections.length,
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 380,
                    mainAxisExtent: cardHeight,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemBuilder: (context, index) => _SettingsSectionCard(
                    item: item,
                    section: item.sections[index],
                    values: values,
                    defaults: defaults,
                    onChanged: onChanged,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          _SettingsDetailFooter(
            lastSavedAt: lastSavedAt,
            dirty: dirty,
            onRevert: onRevert,
            onSave: onSave,
          ),
        ],
      ),
    );
  }
}

class _SettingsProfileHeader extends StatelessWidget {
  const _SettingsProfileHeader({required this.item, required this.dirty});

  final SettingsNavigationItem item;
  final bool dirty;

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: AppColors.surfaceDark.withValues(alpha: .58),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.profileTitle, style: portixTitle(13)),
                const SizedBox(height: 4),
                Text(
                  item.profileSubtitle,
                  overflow: TextOverflow.ellipsis,
                  style: portixMuted(11),
                ),
              ],
            ),
          ),
          AppPill(
            label: dirty ? 'Draft' : 'Synced',
            color: dirty ? AppColors.amber : AppColors.green,
            background: dirty
                ? const Color(0xFF3A2D0B)
                : const Color(0xFF0B3A27),
          ),
        ],
      ),
    );
  }
}

class _SettingsSectionCard extends StatelessWidget {
  const _SettingsSectionCard({
    required this.item,
    required this.section,
    required this.values,
    required this.defaults,
    required this.onChanged,
  });

  final SettingsNavigationItem item;
  final SettingsDetailSection section;
  final Map<String, String> values;
  final Map<String, String> defaults;
  final void Function(String key, String value) onChanged;

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      padding: const EdgeInsets.all(10),
      color: AppColors.surfaceDark.withValues(alpha: .4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(section.title, style: portixTitle(12)),
          const SizedBox(height: 8),
          for (final row in section.rows) ...[
            _SettingsValueRow(
              row: row,
              itemId: item.id,
              value:
                  values[row.keyFor(item.id)] ??
                  defaults[row.keyFor(item.id)] ??
                  row.value,
              onChanged: onChanged,
            ),
            if (row != section.rows.last) const SizedBox(height: 7),
          ],
        ],
      ),
    );
  }
}

class _SettingsValueRow extends StatelessWidget {
  const _SettingsValueRow({
    required this.row,
    required this.itemId,
    required this.value,
    required this.onChanged,
  });

  final SettingsDetailRow row;
  final String itemId;
  final String value;
  final void Function(String key, String value) onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _editSetting(context),
        borderRadius: BorderRadius.circular(7),
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: .52),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  row.label,
                  overflow: TextOverflow.ellipsis,
                  style: portixMuted(10),
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: portixTitle(10).copyWith(
                    color: value == 'ON' || value == 'Enabled'
                        ? AppColors.green
                        : AppColors.text,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.edit_rounded, color: AppColors.muted, size: 12),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editSetting(BuildContext context) async {
    final key = row.keyFor(itemId);
    final options = row.options;
    if (options.isNotEmpty) {
      final selected = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: AppColors.surface,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.label, style: portixTitle(16)),
                const SizedBox(height: 10),
                for (final option in options)
                  ListTile(
                    dense: true,
                    title: Text(option, style: portixTitle(13)),
                    trailing: option == value
                        ? const Icon(
                            Icons.check_rounded,
                            color: AppColors.green,
                          )
                        : null,
                    onTap: () => Navigator.of(context).pop(option),
                  ),
              ],
            ),
          ),
        ),
      );
      if (selected != null) onChanged(key, selected);
      return;
    }

    final controller = TextEditingController(text: value);
    final edited = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(row.label),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Value'),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Apply'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
    if (edited != null && edited.trim().isNotEmpty) {
      onChanged(key, edited.trim());
    }
  }
}

class _SettingsDetailFooter extends StatelessWidget {
  const _SettingsDetailFooter({
    required this.lastSavedAt,
    required this.dirty,
    required this.onRevert,
    required this.onSave,
  });

  final DateTime? lastSavedAt;
  final bool dirty;
  final VoidCallback? onRevert;
  final VoidCallback? onSave;

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      color: AppColors.surfaceDark.withValues(alpha: .52),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _checkpointLabel(),
              overflow: TextOverflow.ellipsis,
              style: portixMuted(10),
            ),
          ),
          AppButton(
            icon: Icons.restore_rounded,
            label: 'Revert',
            onPressed: onRevert,
          ),
          const SizedBox(width: 8),
          AppButton(
            icon: Icons.publish_rounded,
            label: dirty ? 'Apply Changes' : 'Applied',
            primary: true,
            onPressed: onSave,
          ),
        ],
      ),
    );
  }

  String _checkpointLabel() {
    final saved = lastSavedAt;
    if (saved == null) return 'Local settings not saved yet';
    String two(int value) => value.toString().padLeft(2, '0');
    return 'Last saved locally: ${two(saved.day)}/${two(saved.month)}/${saved.year} ${two(saved.hour)}:${two(saved.minute)}';
  }
}
