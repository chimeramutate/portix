import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:portix/src/core/di/injection.dart';
import 'package:portix/src/core/theme/app_theme.dart';
import 'package:portix/src/features/settings/bloc/index.dart';
import 'package:portix/src/features/settings/widget/index.dart';

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

const settingsNavigationGroups = [
  SettingsNavigationGroup(
    label: 'Workspace',
    items: [
      SettingsNavigationItem(
        id: 'general',
        title: 'General',
        icon: Icons.tune_rounded,
        headerTitle: 'Workspace Defaults',
        headerSubtitle: 'Core workspace behavior',
        profileTitle: 'Default Workspace Profile',
        profileSubtitle:
            'Controls baseline behavior for SSH and terminal sessions',
        sections: [
          SettingsDetailSection(
            title: 'Workspace',
            rows: [
              SettingsDetailRow('Theme density', 'Compact'),
              SettingsDetailRow('Profile card mode', 'Detailed'),
              SettingsDetailRow('Terminal font scale', '13 px'),
            ],
          ),
          SettingsDetailSection(
            title: 'Session Defaults',
            rows: [
              SettingsDetailRow('Restore last view', 'Enabled'),
              SettingsDetailRow('Auto focus terminal', 'Enabled'),
              SettingsDetailRow('Remote folder mount', 'Enabled'),
              SettingsDetailRow('Terminal suggestions', 'ON'),
            ],
          ),
        ],
      ),
      SettingsNavigationItem(
        id: 'editor',
        title: 'Editor',
        icon: Icons.code_rounded,
        headerTitle: 'Code Editor Settings',
        headerSubtitle: 'Default editor and file associations',
        profileTitle: 'Editor Profile',
        profileSubtitle:
            'Controls which editor opens files from SFTP and remote folder',
        sections: [
          SettingsDetailSection(
            title: 'Default Editor',
            rows: [
              SettingsDetailRow('Code files', 'VS Code'),
              SettingsDetailRow('Documents', 'System default'),
              SettingsDetailRow('Open behavior', 'Download & open'),
            ],
          ),
          SettingsDetailSection(
            title: 'File Handling',
            rows: [
              SettingsDetailRow('Auto-rewrite prompt', 'Enabled'),
              SettingsDetailRow('Temp file cleanup', 'After close'),
              SettingsDetailRow('Binary file action', 'Download only'),
            ],
          ),
        ],
      ),
      SettingsNavigationItem(
        id: 'teams',
        title: 'Teams',
        icon: Icons.groups_2_outlined,
        headerTitle: 'Team Controls',
        headerSubtitle: 'Shared workspace policy',
        profileTitle: 'Team Access Profile',
        profileSubtitle: 'Controls collaborative profile ownership',
        sections: [
          SettingsDetailSection(
            title: 'Membership',
            rows: [
              SettingsDetailRow('Default role', 'Operator'),
              SettingsDetailRow('Invite approval', 'Required'),
              SettingsDetailRow('Shared profile edits', 'Review'),
            ],
          ),
          SettingsDetailSection(
            title: 'Sync',
            rows: [
              SettingsDetailRow('Team profile sync', 'Enabled'),
              SettingsDetailRow('Conflict strategy', 'Newest valid'),
              SettingsDetailRow('Audit trail', 'Enabled'),
            ],
          ),
        ],
      ),
    ],
  ),
  SettingsNavigationGroup(
    label: 'Security',
    items: [
      SettingsNavigationItem(
        id: 'access',
        title: 'Access',
        icon: Icons.shield_outlined,
        headerTitle: 'Access Policy',
        headerSubtitle: 'Credential and vault behavior',
        profileTitle: 'Credential Guard Profile',
        profileSubtitle: 'Protects SSH credentials and session unlock flow',
        sections: [
          SettingsDetailSection(
            title: 'Vault',
            rows: [
              SettingsDetailRow('Require unlock before connect', 'ON'),
              SettingsDetailRow('Password fallback', 'OFF'),
              SettingsDetailRow('Credential timeout', '20 min'),
            ],
          ),
          SettingsDetailSection(
            title: 'Host Trust',
            rows: [
              SettingsDetailRow('Strict host key checking', 'ON'),
              SettingsDetailRow('Unknown host action', 'Prompt'),
              SettingsDetailRow('Fingerprint display', 'SHA-256'),
            ],
          ),
        ],
      ),
      SettingsNavigationItem(
        id: 'audit',
        title: 'Audit',
        icon: Icons.content_paste_search_outlined,
        headerTitle: 'Audit Policy',
        headerSubtitle: 'Session recording and review',
        profileTitle: 'Audit Capture Profile',
        profileSubtitle: 'Defines what actions are tracked for review',
        sections: [
          SettingsDetailSection(
            title: 'Capture',
            rows: [
              SettingsDetailRow('Session recording', 'Enabled'),
              SettingsDetailRow('Command digest', 'Daily'),
              SettingsDetailRow('Sensitive output redaction', 'ON'),
            ],
          ),
          SettingsDetailSection(
            title: 'Retention',
            rows: [
              SettingsDetailRow('Audit retention', '30 days'),
              SettingsDetailRow('Export format', 'JSONL'),
              SettingsDetailRow('Reviewer route', 'Primary'),
            ],
          ),
        ],
      ),
    ],
  ),
  SettingsNavigationGroup(
    label: 'Mission',
    items: [
      SettingsNavigationItem(
        id: 'configuration',
        title: 'Configuration Center',
        icon: Icons.adjust_rounded,
        headerTitle: 'Mission Config Center',
        headerSubtitle: 'Policy and rollout controls',
        profileTitle: 'Global Configuration Profile',
        profileSubtitle:
            'Controls default behavior for SSH, SFTP, and rollout safety',
        sections: [
          SettingsDetailSection(
            title: 'Session Guardrails',
            rows: [
              SettingsDetailRow('Idle timeout', '20 min'),
              SettingsDetailRow('Max concurrent sessions', '8'),
              SettingsDetailRow('Session recording', 'Enabled'),
            ],
          ),
          SettingsDetailSection(
            title: 'Transfer Automation',
            rows: [
              SettingsDetailRow('Retry strategy', 'Exponential'),
              SettingsDetailRow('Auto resume', 'Enabled'),
              SettingsDetailRow('Integrity verify', 'SHA-256'),
            ],
          ),
          SettingsDetailSection(
            title: 'Compliance Matrix',
            rows: [
              SettingsDetailRow('Host key pinning', 'Required'),
              SettingsDetailRow('Passphrase policy', 'Strong'),
              SettingsDetailRow('Credential rotation', '30 days'),
            ],
          ),
          SettingsDetailSection(
            title: 'Notification Routing',
            rows: [
              SettingsDetailRow('Ops channel', '#infra-alerts'),
              SettingsDetailRow('Pager route', 'Primary'),
              SettingsDetailRow('Digest report', 'Daily'),
            ],
          ),
        ],
      ),
      SettingsNavigationItem(
        id: 'automation',
        title: 'Automation',
        icon: Icons.account_tree_outlined,
        headerTitle: 'Automation Policy',
        headerSubtitle: 'Workflow execution preferences',
        profileTitle: 'Automation Profile',
        profileSubtitle: 'Defines safe defaults for remote actions',
        sections: [
          SettingsDetailSection(
            title: 'Runbooks',
            rows: [
              SettingsDetailRow('Preflight validation', 'Required'),
              SettingsDetailRow('Autofix mode', 'Manual'),
              SettingsDetailRow('Rollback checkpoints', 'Enabled'),
            ],
          ),
          SettingsDetailSection(
            title: 'Scheduling',
            rows: [
              SettingsDetailRow('Maintenance window', '02:00 UTC'),
              SettingsDetailRow('Parallel jobs', '4'),
              SettingsDetailRow('Failure policy', 'Pause'),
            ],
          ),
        ],
      ),
    ],
  ),
  SettingsNavigationGroup(
    label: 'Integrations',
    items: [
      SettingsNavigationItem(
        id: 'connectors',
        title: 'Connectors',
        icon: Icons.cable_rounded,
        headerTitle: 'Connector Settings',
        headerSubtitle: 'External service bindings',
        profileTitle: 'Connector Profile',
        profileSubtitle: 'Routes workspace events to external services',
        sections: [
          SettingsDetailSection(
            title: 'Providers',
            rows: [
              SettingsDetailRow('GitHub', 'Connected'),
              SettingsDetailRow('Jira', 'Available'),
              SettingsDetailRow('Linear', 'Available'),
            ],
          ),
          SettingsDetailSection(
            title: 'Secrets',
            rows: [
              SettingsDetailRow('Token storage', 'Vault'),
              SettingsDetailRow('Rotation reminder', 'Enabled'),
              SettingsDetailRow('Scope validation', 'ON'),
            ],
          ),
        ],
      ),
      SettingsNavigationItem(
        id: 'webhooks',
        title: 'Webhooks',
        icon: Icons.webhook_outlined,
        headerTitle: 'Webhook Routing',
        headerSubtitle: 'Outbound event delivery',
        profileTitle: 'Webhook Profile',
        profileSubtitle: 'Controls alerts and transfer completion callbacks',
        sections: [
          SettingsDetailSection(
            title: 'Delivery',
            rows: [
              SettingsDetailRow('Transfer complete', 'Enabled'),
              SettingsDetailRow('Failure alerts', 'Enabled'),
              SettingsDetailRow('Retry count', '3'),
            ],
          ),
          SettingsDetailSection(
            title: 'Security',
            rows: [
              SettingsDetailRow('Signature', 'HMAC'),
              SettingsDetailRow('Payload format', 'JSON'),
              SettingsDetailRow('Timeout', '10 sec'),
            ],
          ),
        ],
      ),
    ],
  ),
  SettingsNavigationGroup(
    label: 'Runtime',
    items: [
      SettingsNavigationItem(
        id: 'agents',
        title: 'Agents',
        icon: Icons.smart_toy_outlined,
        headerTitle: 'Runtime Agents',
        headerSubtitle: 'Local and remote helper behavior',
        profileTitle: 'Agent Runtime Profile',
        profileSubtitle: 'Controls local helper processes and diagnostics',
        sections: [
          SettingsDetailSection(
            title: 'Local Agent',
            rows: [
              SettingsDetailRow('Auto start', 'Enabled'),
              SettingsDetailRow('Health check', '30 sec'),
              SettingsDetailRow('Crash restart', 'ON'),
            ],
          ),
          SettingsDetailSection(
            title: 'Remote Agent',
            rows: [
              SettingsDetailRow('Install prompt', 'Manual'),
              SettingsDetailRow('Version pinning', 'Enabled'),
              SettingsDetailRow('Telemetry', 'Minimal'),
            ],
          ),
        ],
      ),
    ],
  ),
];
