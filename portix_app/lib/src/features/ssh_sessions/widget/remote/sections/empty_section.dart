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
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: AppPanel(
            padding: const EdgeInsets.all(20),
            color: AppColors.surface,
            radius: 10,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConnectionStatusIcon(
                  icon: Icons.power_settings_new_rounded,
                  color: AppColors.muted,
                  tint: AppColors.selectedSoft,
                ),
                const SizedBox(height: 14),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('No terminal connection', style: portixTitle(15)),
                ),
                const SizedBox(height: 6),
                Text(
                  profile == null
                      ? 'Select an SSH profile to start a terminal session.'
                      : '${profile!.username}@${profile!.name} is not connected.',
                  textAlign: TextAlign.center,
                  style: portixMuted(12).copyWith(height: 1.4),
                ),
                const SizedBox(height: 16),
                if (onConnect != null) ...[
                  SizedBox(
                    width: double.infinity,
                    child: AppButton(
                      icon: Icons.refresh_rounded,
                      label: 'Connect',
                      primary: true,
                      onPressed: onConnect,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                SizedBox(
                  width: double.infinity,
                  child: AppButton(
                    icon: Icons.list_rounded,
                    label: 'View Profiles',
                    onPressed: onViewProfiles,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
