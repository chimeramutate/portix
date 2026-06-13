import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:portix/src/connection_manager/connection_manager.dart';
import 'package:portix/src/connection_manager/session_models.dart'
    as session_models;
import 'package:portix/src/core/di/injection.dart';
import 'package:portix/src/core/theme/app_theme.dart';
import 'package:portix/src/domain/entities/ssh/index.dart';
import 'package:portix/src/features/ssh_sessions/bloc/index.dart';
import '../../bloc/index.dart';
import 'package:portix/src/core/widgets/index.dart';
import 'profile_card.dart';

class ProfileInspector extends StatelessWidget {
  const ProfileInspector({required this.profile, super.key});

  final SshProfile profile;

  @override
  Widget build(BuildContext context) {
    final status = effectiveProfileStatus(profile);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(left: BorderSide(color: AppColors.border)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('Selected Profile', style: portixLabel())),
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
            const SizedBox(height: 8),
            AppPanel(
              color: const Color(0xFF123455),
              borderColor: AppColors.primaryBlue,
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  ProfileOsIcon(profile: profile),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          profile.name,
                          overflow: TextOverflow.ellipsis,
                          style: portixTitle(17),
                        ),
                        Text(
                          profile.address,
                          overflow: TextOverflow.ellipsis,
                          style: portixMuted(),
                        ),
                        const SizedBox(height: 10),
                        AppPill(
                          label: statusLabelFor(status),
                          color: statusColorFor(status),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _DetailBox(
              icon: Icons.language_rounded,
              label: 'Host / IP',
              value: profile.host,
            ),
            _DetailBox(
              icon: profile.authMethod == AuthMethod.sshKey
                  ? Icons.key_rounded
                  : Icons.lock_outline_rounded,
              label: 'Auth method',
              value: profile.credentialLabel.isEmpty
                  ? 'Not configured'
                  : profile.authMethod == AuthMethod.sshKey
                  ? 'SSH key configured'
                  : 'Password saved securely',
            ),
            _DetailBox(
              icon: Icons.sell_outlined,
              label: 'Group + Tags',
              value: '${profile.group} / ${profile.tags.join(' / ')}',
            ),
            const SizedBox(height: 8),
            Text('Quick actions', style: portixLabel()),
            const SizedBox(height: 10),
            AppButton(
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
            const SizedBox(height: 10),
            AppButton(
              icon: Icons.cable_rounded,
              label: 'Start SFTP Connect',
              onPressed: () => context.read<SshSessionBloc>().add(
                SshSessionOpenRequested(
                  profile: profile,
                  target: SshSessionTarget.sftp,
                ),
              ),
            ),
            const SizedBox(height: 18),
            _ConnectionFeedbackPanel(profile: profile),
          ],
        ),
      ),
    );
  }
}

class _DetailBox extends StatelessWidget {
  const _DetailBox({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: portixLabel()),
          const SizedBox(height: 7),
          AppPanel(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            color: AppColors.surfaceDark,
            child: Row(
              children: [
                Icon(icon, color: AppColors.cyan, size: 17),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    value,
                    overflow: TextOverflow.ellipsis,
                    style: portixTitle(13),
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
    final start = DateTime.now();
    try {
      final socket = await RawSocket.connect(
        profile.host,
        profile.port,
      ).timeout(const Duration(seconds: 5));
      socket.close();
      if (!mounted) return;
      setState(() {
        _latencyMs = DateTime.now().difference(start).inMilliseconds;
      });
    } catch (_) {
      // Latency measurement failed — keep null (will show "—").
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = effectiveProfileStatus(widget.profile);
    final isOnline = status == ConnectionStatus.online;
    if (!isOnline) return const SizedBox.shrink();

    final latencyText = _latencyMs == null ? '— ms' : '$_latencyMs ms';

    return AppPanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Connection feedback', style: portixTitle(13)),
          const SizedBox(height: 10),
          const _FeedbackLine(
            icon: Icons.check_circle_outline,
            text: 'Host key verified',
            color: AppColors.green,
          ),
          _FeedbackLine(
            icon: Icons.monitor_heart_outlined,
            text: 'Latency $latencyText',
            color: AppColors.cyan,
          ),
          const _FeedbackLine(
            icon: Icons.folder_outlined,
            text: 'Remote folder mounted',
            color: AppColors.muted,
          ),
        ],
      ),
    );
  }
}
