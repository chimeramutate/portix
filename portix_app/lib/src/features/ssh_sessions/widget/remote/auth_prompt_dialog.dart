import 'package:flutter/material.dart';
import 'package:portix/src/connection_manager/connection_manager.dart';
import 'package:portix/src/connection_manager/session_models.dart';
import 'package:portix/src/connection_manager/ssh_profile.dart';
import 'package:portix/src/core/theme/app_theme.dart';
import 'package:portix/src/core/widgets/index.dart';

/// Answers given so far per `host:port`, one list per keyboard-interactive
/// round; each failed connect asks only for the round it got stuck on.
final Map<String, List<List<String>>> _answeredRounds = {};

/// After a failed connect, asks the keyboard-interactive questions (OTP,
/// 2FA, PAM) the server sent, if that was the cause. Same contract as
/// `resolveRefusedHostKey`: null when it was not the cause, true when
/// answered (connect again), false when cancelled.
Future<bool?> resolveAuthPrompts(
  BuildContext context,
  ConnectionManager manager,
  SshProfile profile,
) async {
  // The prompts may come from a jump host rather than the target.
  AuthPromptRound? found;
  final chain = await manager.credentials
      .connectionChain(profile)
      .catchError((Object _) => [profile]);
  for (final hop in chain) {
    found = await manager.pendingAuthPrompts(hop);
    if (found != null) {
      profile = hop;
      break;
    }
  }
  final round = found;
  if (round == null) return null;
  if (!context.mounted) return false;

  final answers = await showDialog<List<String>>(
    context: context,
    builder: (_) => _AuthPromptDialog(profile: profile, round: round),
  );
  if (answers == null) return false;
  final key = '${profile.host}:${profile.port}';
  final rounds = [...?_answeredRounds[key]?.take(round.round), answers];
  _answeredRounds[key] = rounds;
  await manager.answerAuthPrompts(profile, rounds);
  return true;
}

class _AuthPromptDialog extends StatefulWidget {
  const _AuthPromptDialog({required this.profile, required this.round});

  final SshProfile profile;
  final AuthPromptRound round;

  @override
  State<_AuthPromptDialog> createState() => _AuthPromptDialogState();
}

class _AuthPromptDialogState extends State<_AuthPromptDialog> {
  late final List<TextEditingController> _controllers = [
    for (final _ in widget.round.prompts) TextEditingController(),
  ];

  @override
  void dispose() {
    for (final controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  void _submit() =>
      Navigator.of(context).pop([for (final c in _controllers) c.text]);

  @override
  Widget build(BuildContext context) {
    final round = widget.round;
    final target = '${widget.profile.username}@${widget.profile.host}';
    return AlertDialog(
      backgroundColor: AppColors.surface,
      title: Row(
        children: [
          Icon(Icons.pin_outlined, color: AppColors.cyan),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              round.name.trim().isEmpty ? 'Verification' : round.name.trim(),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              round.instructions.trim().isEmpty
                  ? '$target asks for more information to sign in.'
                  : round.instructions.trim(),
              style: portixMuted(12),
            ),
            for (final (i, p) in round.prompts.indexed) ...[
              const SizedBox(height: 14),
              TextField(
                controller: _controllers[i],
                obscureText: !p.echo,
                autofocus: i == 0,
                decoration: InputDecoration(
                  labelText: p.prompt.trim().replaceFirst(RegExp(r':$'), ''),
                ),
                textInputAction: i == round.prompts.length - 1
                    ? TextInputAction.done
                    : TextInputAction.next,
                onSubmitted: i == round.prompts.length - 1
                    ? (_) => _submit()
                    : null,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Continue')),
      ],
    );
  }
}
