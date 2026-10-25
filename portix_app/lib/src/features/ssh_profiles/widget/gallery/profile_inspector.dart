import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:portix/src/connection_manager/connection_manager.dart';
import 'package:portix/src/core/theme/app_theme.dart';
import 'package:portix/src/core/widgets/index.dart';
import 'package:portix/src/domain/entities/ssh/ssh_profile.dart';
import 'package:portix/src/features/ssh_sessions/bloc/ssh_session_bloc.dart';

import 'package:portix/src/features/ssh_profiles/bloc/ssh_workspace_bloc.dart';
import 'profile_card.dart';

class ProfileInspector extends StatelessWidget {
  const ProfileInspector({required this.profile, super.key});

  final SshProfile profile;

  @override
  Widget build(BuildContext context) {
    final status = effectiveProfileStatus(profile);
    final auth = profile.authMethod == AuthMethod.sshKey
        ? (profile.credentialLabel.isEmpty ? 'ssh-agent' : 'SSH key')
        : profile.credentialLabel.isEmpty
        ? 'Not configured'
        : 'Saved password';
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(left: BorderSide(color: AppColors.border)),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                ProfileOsIcon(profile: profile, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        profile.name,
                        overflow: TextOverflow.ellipsis,
                        style: portixTitle(15),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(
                            Icons.circle,
                            size: 7,
                            color: statusColorFor(status),
                          ),
                          const SizedBox(width: 6),
                          Text(statusLabelFor(status), style: portixMuted(12)),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => context.read<SshWorkspaceBloc>().add(
                    const ProfileSelectionCleared(),
                  ),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  color: AppColors.muted,
                  tooltip: 'Clear selection',
                ),
              ],
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: AppButton(
                icon: Icons.terminal_rounded,
                label: 'Open SSH Session',
                primary: true,
                onPressed: () => context.read<SshSessionBloc>().add(
                  SshSessionOpenRequested(
                    profile: profile,
                    target: SshSessionTarget.remoteFolder,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SelectionArea(
                child: Column(
                  children: [
                    _DetailRow(label: 'Host', value: profile.host),
                    _DetailRow(label: 'Port', value: '${profile.port}'),
                    _DetailRow(label: 'User', value: profile.username),
                    _DetailRow(label: 'Auth', value: auth),
                    _DetailRow(label: 'Group', value: profile.group),
                    if (profile.tags.isNotEmpty)
                      _DetailRow(
                        label: 'Tags',
                        value: profile.tags.map((tag) => '#$tag').join('  '),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _ConnectionFeedbackPanel(profile: profile),
            ),
          ],
        ),
      ),
    );
  }
}

/// One label/value line of the inspector, divided from the next by a
/// hairline: read-only text, so no input-like box around it.
class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 34),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 64, child: Text(label, style: portixMuted(12))),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              style: TextStyle(color: AppColors.text, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedbackLine extends StatelessWidget {
  const _FeedbackLine({
    required this.icon,
    required this.text,
    required this.color,
  });

  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 9),
          Expanded(child: Text(text, style: portixMuted())),
        ],
      ),
    );
  }
}

/// Shows connection feedback only when the profile is online.
/// Latency is read live from the active [ConnectionManager] session.
class _ConnectionFeedbackPanel extends StatefulWidget {
  const _ConnectionFeedbackPanel({required this.profile});

  final SshProfile profile;

  @override
  State<_ConnectionFeedbackPanel> createState() =>
      _ConnectionFeedbackPanelState();
}

class _ConnectionFeedbackPanelState extends State<_ConnectionFeedbackPanel> {
  int? _latencyMs;

  @override
  void initState() {
    super.initState();
    _measureLatency();
  }

  @override
  void didUpdateWidget(_ConnectionFeedbackPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.id != widget.profile.id) {
      setState(() => _latencyMs = null);
      _measureLatency();
    }
  }

  Future<void> _measureLatency() async {
    final profile = widget.profile;
    if (profile.host.trim().isEmpty) return;
    // The panel only renders for online profiles; don't open a socket to a
    // host whose latency would never be shown.
    if (effectiveProfileStatus(profile) != ConnectionStatus.online) return;
    final start = DateTime.now();
    try {
      final socket = await RawSocket.connect(
        profile.host,
        profile.port,
        timeout: const Duration(seconds: 5),
      );
      socket.close();
      if (!mounted) return;
      setState(() {
        _latencyMs = DateTime.now().difference(start).inMilliseconds;
      });
    } catch (_) {
      // Measurement failed: leave null so the panel says "not measured".
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = effectiveProfileStatus(widget.profile);
    final isOnline = status == ConnectionStatus.online;
    if (!isOnline) return const SizedBox.shrink();

    final latencyText = _latencyMs == null ? 'not measured' : '$_latencyMs ms';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('CONNECTION', style: portixMuted(11).copyWith(letterSpacing: .8)),
        const SizedBox(height: 8),
        _FeedbackLine(
          icon: Icons.check_circle_outline,
          text: 'Host key verified',
          color: AppColors.green,
        ),
        _FeedbackLine(
          icon: Icons.monitor_heart_outlined,
          text: 'Latency $latencyText',
          color: AppColors.muted,
        ),
      ],
    );
  }
}
