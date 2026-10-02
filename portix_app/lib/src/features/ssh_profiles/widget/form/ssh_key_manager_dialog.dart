import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:portix/src/core/theme/app_theme.dart';
import 'package:portix/src/core/widgets/index.dart';
import 'package:portix/src/rust/api.dart' as rust_api;

String get _sshDir {
  final home =
      Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
  return '$home${Platform.pathSeparator}.ssh';
}

/// Lists keypairs in ~/.ssh, browses for a key file, or generates a new
/// ed25519 keypair. Returns the selected private key path, or null.
Future<String?> showSshKeyManager(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (context) => const _SshKeyManagerDialog(),
  );
}

class _SshKeyManagerDialog extends StatefulWidget {
  const _SshKeyManagerDialog();

  @override
  State<_SshKeyManagerDialog> createState() => _SshKeyManagerDialogState();
}

class _SshKeyManagerDialogState extends State<_SshKeyManagerDialog> {
  // Private key path -> public key line.
  Map<String, String> _keys = {};

  @override
  void initState() {
    super.initState();
    _loadKeys();
  }

  Future<void> _loadKeys() async {
    final keys = <String, String>{};
    final dir = Directory(_sshDir);
    if (await dir.exists()) {
      await for (final entity in dir.list()) {
        if (entity is! File || !entity.path.endsWith('.pub')) continue;
        final privatePath = entity.path.substring(0, entity.path.length - 4);
        if (!await File(privatePath).exists()) continue;
        keys[privatePath] = (await entity.readAsString()).trim();
      }
    }
    if (mounted) setState(() => _keys = keys);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _copyPublicKey(String publicKey) async {
    await Clipboard.setData(ClipboardData(text: publicKey));
    _toast('Public key copied. Add it to ~/.ssh/authorized_keys on the server.');
  }

  Future<void> _browse() async {
    final result = await FilePicker.pickFiles(
      dialogTitle: 'Select SSH private key',
      initialDirectory: _sshDir,
    );
    final path = result?.files.single.path;
    if (path != null && mounted) Navigator.of(context).pop(path);
  }

  Future<void> _generate() async {
    final name = TextEditingController(text: 'id_portix_ed25519');
    final comment = TextEditingController(
      text: '${Platform.environment['USER'] ?? 'portix'}@portix',
    );
    final passphrase = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surfaceCard,
        title: Text('Generate ed25519 key', style: portixTitle(16)),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppTextField(controller: name, label: 'File name in ~/.ssh'),
              const SizedBox(height: 12),
              AppTextField(controller: comment, label: 'Comment'),
              const SizedBox(height: 12),
              AppTextField(
                controller: passphrase,
                label: 'Passphrase (optional)',
                obscureText: true,
              ),
              const SizedBox(height: 8),
              Text(
                'Saved with mode 0600. With a passphrase, Portix asks for it '
                'on first connect and keeps it in the system keychain.',
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
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Generate'),
          ),
        ],
      ),
    );
    final fileName = name.text.trim();
    final keyComment = comment.text.trim();
    final keyPassphrase = passphrase.text;
    name.dispose();
    comment.dispose();
    passphrase.dispose();
    if (confirmed != true) return;
    if (fileName.isEmpty || fileName.contains(RegExp(r'[/\\]'))) {
      _toast('File name must not be empty or contain path separators.');
      return;
    }
    final path = '$_sshDir${Platform.pathSeparator}$fileName';
    try {
      final publicKey = await rust_api.generateEd25519Key(
        path: path,
        comment: keyComment,
        passphrase: keyPassphrase.isEmpty ? null : keyPassphrase,
      );
      await _copyPublicKey(publicKey);
      if (mounted) Navigator.of(context).pop(path);
    } catch (error) {
      _toast('Failed to generate key: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 540),
        child: AppPanel(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.key_rounded, color: AppColors.cyan),
                  const SizedBox(width: 10),
                  Expanded(child: Text('SSH keys', style: portixTitle(18))),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(_sshDir, style: portixMuted(11)),
              const SizedBox(height: 12),
              if (_keys.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Text(
                    'No keypairs found. Generate one or browse for a key file.',
                    style: portixMuted(12),
                  ),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final MapEntry(key: path, value: publicKey)
                          in _keys.entries)
                        ListTile(
                          dense: true,
                          title: Text(
                            path.split(Platform.pathSeparator).last,
                            style: portixTitle(13),
                          ),
                          subtitle: Text(
                            publicKey,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              color: AppColors.muted,
                              fontSize: 11,
                            ),
                          ),
                          onTap: () => Navigator.of(context).pop(path),
                          trailing: IconButton(
                            tooltip: 'Copy public key',
                            onPressed: () => _copyPublicKey(publicKey),
                            icon: const Icon(
                              Icons.copy_rounded,
                              color: AppColors.muted,
                              size: 16,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppButton(
                    icon: Icons.folder_open_rounded,
                    label: 'Browse...',
                    onPressed: _browse,
                  ),
                  const SizedBox(width: 8),
                  AppButton(
                    icon: Icons.add_rounded,
                    label: 'Generate ed25519',
                    onPressed: _generate,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
