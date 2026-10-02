import 'package:flutter/material.dart';
import 'package:portix/src/connection_manager/profile_credentials.dart';
import 'package:portix/src/connection_manager/session_models.dart';
import 'package:portix/src/connection_manager/ssh_profile.dart';
import 'package:portix/src/core/theme/app_theme.dart';
import 'package:portix/src/core/widgets/index.dart';

/// Handles a connect [error] caused by an encrypted key: reuses the saved
/// passphrase or asks for one. True when connecting again makes sense.
Future<bool> resolveKeyPassphrase(
  BuildContext context,
  ProfileCredentials credentials,
  SshProfile profile,
  Object error,
) async {
  final problem = keyPassphraseProblemOf(error);
  if (problem == null) return false;
  credentials.useSavedKeyPassphrase(profile.id);
  if (problem == KeyPassphraseProblem.required &&
      await credentials.hasSavedPassword(profile.id)) {
    // The keychain already has it; that connect just didn't send it.
    return true;
  }
  if (!context.mounted) return false;
  final passphrase = await askKeyPassphrase(
    context,
    keyPath: profile.privateKeyPath ?? '',
    problem: problem,
  );
  if (passphrase == null) return false;
  await credentials.savePassword(profile.id, passphrase);
  return true;
}

/// Asks for an encrypted key's passphrase. Returns null when cancelled.
Future<String?> askKeyPassphrase(
  BuildContext context, {
  required String keyPath,
  required KeyPassphraseProblem problem,
}) async {
  final controller = TextEditingController();
  final passphrase = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.surface,
      title: const Text('SSH key passphrase'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              problem == KeyPassphraseProblem.incorrect
                  ? 'The passphrase for $keyPath was wrong. Try again.'
                  : '$keyPath is encrypted. Enter its passphrase; it is '
                        'stored in the system keychain.',
              style: portixMuted(12),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Passphrase'),
              onSubmitted: (value) => Navigator.of(context).pop(value),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: const Text('Unlock and connect'),
        ),
      ],
    ),
  );
  controller.dispose();
  return (passphrase ?? '').isEmpty ? null : passphrase;
}
