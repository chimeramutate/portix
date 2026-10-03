import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:portix/src/core/di/injection.dart';
import 'package:portix/src/core/theme/app_theme.dart';
import 'package:portix/src/features/settings/bloc/index.dart';
import 'package:portix/src/features/settings/widget/index.dart';
import 'package:portix/src/features/ssh_sessions/widget/remote/terminal_settings.dart';
import 'package:portix/src/features/ssh_sessions/widget/remote/terminal_themes.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  SettingsNavigationItem _selectedItem(String selectedId) {
    for (final group in settingsNavigationGroups) {
      for (final item in group.items) {
        if (item.id == selectedId) return item;
      }
    }
    return settingsNavigationGroups.first.items.first;
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          sl<SettingsBloc>()
            ..add(SettingsStarted(defaults: _defaultSettingsValues())),
      child: BlocConsumer<SettingsBloc, SettingsState>(
        listener: (context, state) {
          if (state.message.isEmpty) return;
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: AppColors.surfaceCard,
                behavior: SnackBarBehavior.floating,
              ),
            );
        },
        builder: (context, state) {
          final selectedItem = _selectedItem(state.selectedId);
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                SettingsActionBar(
                  title: selectedItem.headerTitle,
                  subtitle: selectedItem.headerSubtitle,
                  dirty: state.dirty,
                  busy: state.busy,
                  onReset: () =>
                      context.read<SettingsBloc>().add(const SettingsReset()),
                  onRevert: state.dirty
                      ? () => context.read<SettingsBloc>().add(
                          const SettingsReverted(),
                        )
                      : null,
                  onSave: state.dirty && !state.busy
                      ? () => context.read<SettingsBloc>().add(
                          const SettingsSaved(),
                        )
                      : null,
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final narrow = constraints.maxWidth < 980;
                      final navigation = SettingsNavigationPanel(
                        groups: settingsNavigationGroups,
                        selectedId: state.selectedId,
                        onSelected: (id) => context.read<SettingsBloc>().add(
                          SettingsSectionSelected(id),
                        ),
                      );
                      final detail = SettingsDetailPanel(
                        item: selectedItem,
                        values: state.draftValues,
                        defaults: state.defaults,
                        lastSavedAt: state.lastSavedAt,
                        dirty: state.dirty,
                        onChanged: (key, value) => context
                            .read<SettingsBloc>()
                            .add(SettingsValueChanged(key: key, value: value)),
                        onRevert: state.dirty
                            ? () => context.read<SettingsBloc>().add(
                                const SettingsReverted(),
                              )
                            : null,
                        onSave: state.dirty && !state.busy
                            ? () => context.read<SettingsBloc>().add(
                                const SettingsSaved(),
                              )
                            : null,
                      );
                      if (narrow) {
                        return ListView(
                          children: [
                            SizedBox(height: 470, child: navigation),
                            const SizedBox(height: 14),
                            SizedBox(height: 640, child: detail),
                          ],
                        );
                      }
                      return Row(
                        children: [
                          SizedBox(
                            width: constraints.maxWidth * .49,
                            child: navigation,
                          ),
                          const SizedBox(width: 14),
                          Expanded(child: detail),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Map<String, String> _defaultSettingsValues() {
    return {
      for (final group in settingsNavigationGroups)
        for (final item in group.items)
          for (final section in item.sections)
            for (final row in section.rows) row.keyFor(item.id): row.value,
    };
  }
}

/// Only settings the app reads. Keys are `<item id>.<row label>`, so ids and
/// labels must not change (saved values would be lost).
const settingsNavigationGroups = [
  SettingsNavigationGroup(
    label: 'Workspace',
    items: [
      SettingsNavigationItem(
        id: 'general',
        title: 'Terminal',
        icon: Icons.terminal_rounded,
        headerTitle: 'Terminal',
        headerSubtitle: 'Look and shortcuts of SSH terminals',
        profileTitle: 'Terminal Defaults',
        profileSubtitle: 'Applies to every SSH terminal tab',
        sections: [
          SettingsDetailSection(
            title: 'Appearance',
            rows: [
              SettingsDetailRow('Terminal theme', 'Portix', terminalThemeNames),
              SettingsDetailRow('Terminal font', 'Monospace', terminalFonts),
              SettingsDetailRow(
                'Terminal font scale',
                '13 px',
                terminalFontSizes,
              ),
            ],
          ),
          SettingsDetailSection(
            title: 'Shortcuts',
            rows: [
              SettingsDetailRow('Terminal copy shortcut', 'Shift+Ctrl+C'),
              SettingsDetailRow('Terminal paste shortcut', 'Ctrl+V'),
            ],
          ),
        ],
      ),
    ],
  ),
];
