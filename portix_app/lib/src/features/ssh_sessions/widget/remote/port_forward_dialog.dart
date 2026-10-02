import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:portix/src/connection_manager/connection_manager.dart';
import 'package:portix/src/connection_manager/session_models.dart';
import 'package:portix/src/connection_manager/ssh_profile.dart';
import 'package:portix/src/core/theme/app_theme.dart';
import 'package:portix/src/core/widgets/index.dart';

import 'host_key_dialog.dart';

/// Lists running tunnels and starts local forwards (`ssh -L`) through
/// [profile]'s server.
Future<void> showPortForwardDialog(
  BuildContext context,
  ConnectionManager manager,
  SshProfile profile,
) {
  return showDialog<void>(
    context: context,
    builder: (_) => _PortForwardDialog(manager: manager, profile: profile),
  );
}

class _PortForwardDialog extends StatefulWidget {
  const _PortForwardDialog({required this.manager, required this.profile});

  final ConnectionManager manager;
  final SshProfile profile;

  @override
  State<_PortForwardDialog> createState() => _PortForwardDialogState();
}

class _PortForwardDialogState extends State<_PortForwardDialog> {
  final _localPort = TextEditingController();
  final _remoteHost = TextEditingController(text: '127.0.0.1');
  final _remotePort = TextEditingController();
  List<PortForward> _forwards = const [];
  String? _error;
  bool _starting = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _localPort.dispose();
    _remoteHost.dispose();
    _remotePort.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final forwards = await widget.manager.listLocalForwards();
    if (mounted) setState(() => _forwards = forwards);
  }

  int? _port(String text, {required bool allowZero}) {
    final port = int.tryParse(text.trim());
    if (port == null || port > 65535 || port < (allowZero ? 0 : 1)) {
      return null;
    }
    return port;
  }

  Future<void> _start() async {
    final localPort = _localPort.text.trim().isEmpty
        ? 0
        : _port(_localPort.text, allowZero: true);
    final remotePort = _port(_remotePort.text, allowZero: false);
    final remoteHost = _remoteHost.text.trim();
    if (localPort == null || remotePort == null || remoteHost.isEmpty) {
      setState(() => _error = 'Enter a remote host and valid ports (1-65535).');
      return;
    }
    setState(() {
      _starting = true;
      _error = null;
    });
    Future<String?> attempt() async {
      final result = await widget.manager.startLocalForward(
        widget.profile,
        localPort: localPort,
        remoteHost: remoteHost,
        remotePort: remotePort,
      );
      return result.fold((failure) => '$failure', (_) => null);
    }

    var error = await attempt();
    if (error != null && mounted) {
      // Tunnels use their own SSH connection, so an unknown host key can
      // surface here first; trusting it lets us try once more.
      final hostKey = await resolveRefusedHostKey(
        context,
        widget.manager,
        widget.profile,
      );
      if (hostKey == true) error = await attempt();
      if (hostKey == false) error = 'Host key not trusted.';
    }
    if (!mounted) return;
    setState(() {
      _starting = false;
      _error = error;
    });
    if (error == null) {
      _localPort.clear();
      _remotePort.clear();
      await _reload();
    }
  }

  Future<void> _stop(PortForward forward) async {
    await widget.manager.stopLocalForward(forward.id);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Row(
        children: [
          Icon(Icons.swap_horiz_rounded, color: AppColors.cyan),
          SizedBox(width: 10),
          Text('Port forwarding'),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_forwards.isEmpty)
              Text('No tunnels running.', style: portixMuted(12))
            else
              for (final forward in _forwards)
                _ForwardRow(forward: forward, onStop: () => _stop(forward)),
            const Divider(height: 28),
            Text(
              'New tunnel via ${widget.profile.username}@${widget.profile.host}',
              style: portixTitle(13),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                SizedBox(
                  width: 110,
                  child: AppTextField(
                    controller: _localPort,
                    label: 'Local port',
                    hint: 'auto',
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(10, 22, 10, 0),
                  child: Icon(Icons.arrow_forward_rounded, size: 16),
                ),
                Expanded(
                  child: AppTextField(
                    controller: _remoteHost,
                    label: 'Remote host',
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 110,
                  child: AppTextField(
                    controller: _remotePort,
                    label: 'Remote port',
                    hint: '5432',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Remote host is resolved on the server (127.0.0.1 = the server '
              'itself). Local port listens on 127.0.0.1 only.',
              style: portixMuted(11),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: portixMuted(12).copyWith(color: AppColors.danger),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        FilledButton.icon(
          onPressed: _starting ? null : _start,
          icon: _starting
              ? const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.play_arrow_rounded, size: 16),
          label: const Text('Start tunnel'),
        ),
      ],
    );
  }
}

class _ForwardRow extends StatelessWidget {
  const _ForwardRow({required this.forward, required this.onStop});

  final PortForward forward;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final local = '127.0.0.1:${forward.localPort}';
    return Row(
      children: [
        const Icon(Icons.circle, size: 8, color: AppColors.green),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '$local → ${forward.remoteHost}:${forward.remotePort}',
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: AppColors.text,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Copy $local',
          onPressed: () => Clipboard.setData(ClipboardData(text: local)),
          icon: const Icon(Icons.copy_rounded, size: 16),
        ),
        IconButton(
          tooltip: 'Stop tunnel',
          onPressed: onStop,
          icon: const Icon(Icons.stop_circle_outlined, size: 18),
        ),
      ],
    );
  }
}
