import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:portix/src/connection_manager/connection_manager.dart';
import 'package:portix/src/connection_manager/session_models.dart';
import 'package:portix/src/connection_manager/ssh_profile.dart';
import 'package:portix/src/core/theme/app_theme.dart';
import 'package:portix/src/core/widgets/index.dart';

/// After a failed connect, explains a refused server host key, if that was
/// the cause. Returns null when no host key was refused (show the usual
/// error), true when the user trusted a new host's key (connect again), and
/// false when the user cancelled or the key *changed* (never trusted here).
Future<bool?> resolveRefusedHostKey(
  BuildContext context,
  ConnectionManager manager,
  SshProfile profile,
) async {
  // The refused key may belong to a jump host rather than the target.
  HostKeyInfo? found;
  final chain = await manager
      .connectionChain(profile)
      .catchError((Object _) => [profile]);
  for (final hop in chain) {
    found = await manager.pendingHostKey(hop);
    if (found != null) {
      profile = hop;
      break;
    }
  }
  final info = found;
  if (info == null) return null;
  if (!context.mounted) return false;
  final target = profile.port == 22
      ? profile.host
      : '[${profile.host}]:${profile.port}';

  if (info.changed) {
    await showDialog<void>(
      context: context,
      builder: (_) => _HostKeyChangedDialog(target: target, info: info),
    );
    return false;
  }

  final trusted = await showDialog<bool>(
    context: context,
    builder: (_) => _UnknownHostKeyDialog(target: target, info: info),
  );
  if (trusted != true || !context.mounted) return false;
  final result = await manager.trustHostKey(profile, info.fingerprint);
  if (result.isLeft && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.fold((f) => '$f', (_) => ''))),
    );
  }
  return result.isRight;
}

class _UnknownHostKeyDialog extends StatelessWidget {
  const _UnknownHostKeyDialog({required this.target, required this.info});

  final String target;
  final HostKeyInfo info;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Row(
        children: [
          Icon(Icons.fingerprint_rounded, color: AppColors.cyan),
          SizedBox(width: 10),
          Text('Verify host key'),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Portix has not connected to $target before. Check that the '
              'fingerprint below matches the server before trusting it.',
              style: portixMuted(12),
            ),
            const SizedBox(height: 14),
            _FingerprintBox(
              algorithm: info.algorithm,
              fingerprint: info.fingerprint,
            ),
            const SizedBox(height: 10),
            Text(
              'On the server: ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub',
              style: portixMuted(11),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Icons.verified_user_outlined, size: 16),
          label: const Text('Trust and connect'),
        ),
      ],
    );
  }
}

class _HostKeyChangedDialog extends StatelessWidget {
  const _HostKeyChangedDialog({required this.target, required this.info});

  final String target;
  final HostKeyInfo info;

  @override
  Widget build(BuildContext context) {
    final removeCommand = 'ssh-keygen -R "$target"';
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Row(
        children: [
          Icon(Icons.gpp_bad_outlined, color: AppColors.danger),
          SizedBox(width: 10),
          Text('Host key changed'),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The key offered by $target does not match the one recorded on '
              'line ${info.changedLine} of ~/.ssh/known_hosts. Someone may be '
              'intercepting the connection, so Portix refused to connect.',
              style: portixMuted(12),
            ),
            const SizedBox(height: 14),
            _FingerprintBox(
              algorithm: info.algorithm,
              fingerprint: info.fingerprint,
            ),
            const SizedBox(height: 14),
            Text(
              'Only if you know the server key changed (e.g. reinstall), remove '
              'the old entry and connect again:',
              style: portixMuted(12),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: SelectableText(
                    removeCommand,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: AppColors.text,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Copy command',
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: removeCommand)),
                  icon: const Icon(Icons.copy_rounded, size: 16),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _FingerprintBox extends StatelessWidget {
  const _FingerprintBox({required this.algorithm, required this.fingerprint});

  final String algorithm;
  final String fingerprint;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.terminal,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: SelectableText(
        '$algorithm\n$fingerprint',
        style: const TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          height: 1.4,
          color: AppColors.text,
        ),
      ),
    );
  }
}
