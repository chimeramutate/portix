part of '../terminal_workspace_view.dart';

class TerminalConnectionOverlay extends StatelessWidget {
  const TerminalConnectionOverlay({
    required this.profile,
    required this.connecting,
    required this.onReconnect,
  });

  final domain.SshProfile? profile;
  final bool connecting;
  final VoidCallback? onReconnect;

  @override
  Widget build(BuildContext context) {
    final label = profile == null
        ? 'This terminal session is not connected.'
        : '${profile!.username}@${profile!.name} is not connected.';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.terminal.withValues(alpha: .86),
      ),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(10),
          child: AppPanel(
            padding: const EdgeInsets.all(16),
            color: AppColors.surfaceDark.withValues(alpha: .96),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (connecting)
                    const SizedBox.square(
                      dimension: 26,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    const Icon(
                      Icons.link_off_rounded,
                      color: AppColors.amber,
                      size: 30,
                    ),
                  const SizedBox(height: 10),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      connecting
                          ? 'Connecting session'
                          : 'Session disconnected',
                      style: portixTitle(15),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: portixMuted(12),
                  ),
                  if (!connecting && onReconnect != null) ...[
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 34,
                      child: OutlinedButton.icon(
                        onPressed: onReconnect,
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text('Reconnect'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
