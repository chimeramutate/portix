part of '../terminal_workspace_view.dart';

class TerminalSessionTab extends StatelessWidget {
  const TerminalSessionTab({
    required this.sessionId,
    required this.label,
    this.active = false,
    this.status = session_models.ConnectionStatus.connected,
    this.leadingIcon,
    this.draggable = true,
    this.onTap,
    this.onClose,
    this.onReconnect,
    this.reconnectNearClose = false,
  });

  final String sessionId;
  final String label;
  final bool active;
  final session_models.ConnectionStatus status;
  final IconData? leadingIcon;
  final bool draggable;
  final VoidCallback? onTap;
  final VoidCallback? onClose;
  final VoidCallback? onReconnect;
  final bool reconnectNearClose;

  @override
  Widget build(BuildContext context) {
    final connected = status == session_models.ConnectionStatus.connected;
    final connecting = status == session_models.ConnectionStatus.connecting;
    final canReconnect =
        status == session_models.ConnectionStatus.disconnected ||
        status == session_models.ConnectionStatus.error;
    final tab = GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        width: 200,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF143B63) : AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? AppColors.primaryBlue : AppColors.border,
          ),
        ),
        child: Row(
          children: [
            if (canReconnect && onReconnect != null && !reconnectNearClose)
              SizedBox.square(
                dimension: 24,
                child: IconButton(
                  tooltip: 'Reconnect $label',
                  onPressed: onReconnect,
                  padding: EdgeInsets.zero,
                  icon: const Icon(
                    Icons.refresh_rounded,
                    color: AppColors.amber,
                    size: 17,
                  ),
                ),
              )
            else
              Icon(
                leadingIcon ?? (connecting ? Icons.sync_rounded : Icons.circle),
                size: leadingIcon == null && !connecting ? 9 : 17,
                color: connected && active ? AppColors.green : AppColors.muted,
              ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: portixTitle(13),
              ),
            ),
            if (canReconnect && onReconnect != null && reconnectNearClose)
              SizedBox.square(
                dimension: 24,
                child: IconButton(
                  tooltip: 'Reconnect $label',
                  onPressed: onReconnect,
                  padding: EdgeInsets.zero,
                  icon: const Icon(
                    Icons.refresh_rounded,
                    color: AppColors.amber,
                    size: 17,
                  ),
                ),
              ),
            if (canReconnect && onReconnect != null && reconnectNearClose)
              const SizedBox(width: 4),
            SizedBox.square(
              dimension: 24,
              child: IconButton(
                key: ValueKey('close-tab-$label'),
                onPressed: onClose,
                padding: EdgeInsets.zero,
                tooltip: 'Close $label',
                icon: const Icon(
                  Icons.close_rounded,
                  color: AppColors.muted,
                  size: 17,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (!draggable) return tab;
    return Draggable<String>(
      data: sessionId,
      onDragStarted: () => PaneDragHandle.dragging.value = true,
      onDragEnd: (_) => PaneDragHandle.dragging.value = false,
      onDraggableCanceled: (_, _) => PaneDragHandle.dragging.value = false,
      feedback: Material(color: Colors.transparent, child: tab),
      childWhenDragging: Opacity(opacity: .45, child: tab),
      child: tab,
    );
  }
}

class SessionProfileOption extends StatelessWidget {
  const SessionProfileOption({required this.profile, required this.onSelected});

  final domain.SshProfile profile;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('new-session-profile-${profile.id}'),
        onTap: onSelected,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surfaceDark,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.surfaceCard,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: AppColors.primaryBlue),
                ),
                child: const Icon(
                  Icons.dns_rounded,
                  color: AppColors.green,
                  size: 19,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(profile.name, style: portixTitle(14)),
                    const SizedBox(height: 2),
                    Text(
                      profile.address,
                      overflow: TextOverflow.ellipsis,
                      style: portixMuted(12),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}
