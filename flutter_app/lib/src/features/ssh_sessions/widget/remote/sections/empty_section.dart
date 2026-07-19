part of '../terminal_workspace_view.dart';

class NoTerminalConnection extends StatelessWidget {
  const NoTerminalConnection({
    required this.profile,
    required this.onConnect,
    this.onViewProfiles,
  });
  final domain.SshProfile? profile;
  final VoidCallback? onConnect;
  final VoidCallback? onViewProfiles;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.terminal,
      alignment: Alignment.center,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: AppPanel(
          padding: const EdgeInsets.all(18),
          color: AppColors.surfaceDark,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.power_settings_new_rounded,
                  color: AppColors.muted,
                  size: 36,
                ),
                const SizedBox(height: 12),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('No terminal connection', style: portixTitle(16)),
                ),
                const SizedBox(height: 8),
                Text(
                  profile == null
                      ? 'Select an SSH profile to start a terminal session.'
                      : '${profile!.username}@${profile!.name} is not connected.',
                  textAlign: TextAlign.center,
                  style: portixMuted(12),
                ),
                const SizedBox(height: 14),
                Column(
                  children: [
                    if (onConnect != null) ...[
                      SizedBox(
                        width: double.infinity,
                        height: 34,
                        child: OutlinedButton.icon(
                          onPressed: onConnect,
                          icon: const Icon(Icons.refresh_rounded, size: 16),
                          label: const Text('Connect'),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                    SizedBox(
                      width: double.infinity,
                      height: 34,
                      child: AppButton(
                        icon: Icons.list_rounded,
                        label: 'View Profiles',
                        onPressed: onViewProfiles,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
